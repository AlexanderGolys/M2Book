referencePackage := currentPackage

needsPackage "Macaulay2Doc"
needsPackage "JSON"
needsPackage "Text"

load "./reference/extractCommon.m2"
load "./reference/extractFunc.m2"
load "./reference/extractType.m2"
load "./reference/extractOperator.m2"
load "./reference/extractPackage.m2"
-- the reference pages of a corpus, and the LSP index assembled from them
load "./reference/pages.m2"
load "./reference/index.m2"

-- Standard distribution package entry points. Script mode (-q) intentionally
-- omits user-installed package paths, so this list excludes local packages.
-- `searchPath` includes both the source and installed package directories;
-- deduplication makes the result independent of the active M2 layout.
standardPackageNames = () -> (
    packageDirs := searchPath "A1BrouwerDegrees.m2";
    if #packageDirs == 0 then error "cannot locate the standard M2 package directory";
    sort unique prepend("Core", flatten apply(packageDirs, dir ->
        apply(
            select(readDirectory dir,
                filename -> match("^[A-Za-z][A-Za-z0-9]*[.]m2$", filename)),
            filename -> replace("[.]m2$", "", filename)
        )))
)

-- Canonical top-level record names owned by one package. This is used to shard
-- exceptionally large packages (Core) without splitting aliases of the same
-- runtime object across workers.
packageReferenceNames = packageName -> (
    pkg := needsPackage packageName;
    runtimeDict := new MutableHashTable;
    scan(keys pkg.Dictionary, key -> runtimeDict#key = pkg.Dictionary#key);
    operatorNames := select(sort apply(keys operatorAttributes, toString), name -> (
        sym := symbolForName(runtimeDict, name);
        sym =!= null and packageForSymbol sym === packageName
    ));
    allNames := sort unique select(
        apply(
            join({packageName}, join(apply(keys runtimeDict, toString), operatorNames)),
            shortNameForRecordName),
        name -> not match("^o[0-9]+$", name));
    nameSet := set allNames;
    select(allNames, name -> (
        sym := symbolForName(runtimeDict, name);
        if sym === null or packageForSymbol sym =!= packageName then
            false
        else (
            val := valueForSymbol sym;
            if val === valueFailed then
                false
            else (
                cp := try toString val;
                -- a variable is never an alias, whatever value it holds now
                aliasDuplicate := not isMutable sym and cp =!= null and cp =!= name and nameSet#?cp and (
                    canonicalSym := symbolForName(runtimeDict, cp);
                    canonicalSym =!= null and (valueForSymbol canonicalSym) === val
                );
                kind := recordKind(sym, val, safeClass val, name);
                not aliasDuplicate and (
                    shouldExtractName name
                    or (kind === "operator" and not hasNonAscii name)
                )
            )
        )
    ))
)

-- Second-pass cross references for type records:
--   constructorsForType[T] = functions whose typical_value is T
--   commonOpsForType[T]     = functions with a method whose domain includes T
buildTypeCrossReferences := recordsByName -> (
    constructorsForType := new MutableHashTable;
    commonOpsForType := new MutableHashTable;
    scan(keys recordsByName, name -> (
        rec := recordsByName#name;
        if rec === null then
            return;
        if rec#KindFun === "function" or rec#KindFun === "methodFunction" then (
            funcNorm := rec#NormalizedNameFun;
            tv := if rec#?TypicalValueFieldFun and rec#TypicalValueFieldFun =!= null then rec#TypicalValueFieldFun;
            if tv =!= null then
                constructorsForType#tv = append(constructorsForType#tv ?? {}, funcNorm);
            meths := if rec#?MethodsFun then rec#MethodsFun else {};
            scan(meths, m -> (
                domain := if m#?DomainFun then m#DomainFun else {};
                scan(domain, d -> commonOpsForType#d = append(commonOpsForType#d ?? {}, funcNorm))
            ))
        )
    ));
    (constructorsForType, commonOpsForType)
)

-- Second-pass cross reference for symbol records:
--   optionKeyFor[K] = functions/method functions that accept option key K,
-- counting both top-level options and per-installation method options.
buildOptionKeyCrossReferences := recordsByName -> (
    optionKeyFor := new MutableHashTable;
    scan(
        keys recordsByName, name -> (
        rec := recordsByName#name;
        if rec === null then
            return;
        if rec#KindFun === "function" or rec#KindFun === "methodFunction" then (
            funcNorm := rec#NormalizedNameFun;
            opts := if rec#?OptionsFun then rec#OptionsFun else {};
            meths := if rec#?MethodsFun then rec#MethodsFun else {};
            allOpts := join(opts, flatten apply(meths, m -> if m#?OptionsFun then m#OptionsFun else {}));
            scan(allOpts, o -> if instance(o, HashTable) and o#?KeyFun then (
                k := o#KeyFun;
                optionKeyFor#k = append(optionKeyFor#k ?? {}, funcNorm)
            ))
        )
    ));
    optionKeyFor
)

-- Fill the cross-record fields after extraction. Multi-package extraction calls
-- buildReference once per package so progress can be reported at package
-- boundaries, then calls this again on the combined corpus to retain the global
-- second-pass behavior.
enrichCrossReferences := present -> (
    recordsByName := new MutableHashTable;
    scan(present, r -> recordsByName#(r#NameFun) = r);
    (constructorsForType, commonOpsForType) := buildTypeCrossReferences recordsByName;
    scan(select(present, r -> r#KindFun === "type"), rec -> (
        typeNorm := rec#NormalizedNameFun;
        typeName := rec#NameFun;
        rec#ConstructorsFun = sort unique join(
            sort unique(constructorsForType#typeNorm ?? {}),
            sort unique(constructorsForType#typeName ?? {})
        );
        rec#CommonOperationsFun = sort unique join(
            sort unique(commonOpsForType#typeNorm ?? {}),
            sort unique(commonOpsForType#typeName ?? {})
        )
    ));
    optionKeyFor := buildOptionKeyCrossReferences recordsByName;
    scan(select(present, r -> r#KindFun === "symbol"), rec -> (
        rec#OptionKeyForFun = sort unique join(
            sort unique(optionKeyFor#(rec#NormalizedNameFun) ?? {}),
            sort unique(optionKeyFor#(rec#NameFun) ?? {})
        )
    ));
    present
)

-- Build the full record list. `debugNames` empty = every visible symbol.
-- `targetPackages` (a List of package names, or null) restricts the corpus to
-- those packages; null keeps every visible symbol (home package recorded, not
-- filtered). E.g. {"Core"} for the core corpus, or the default-loaded set plus
-- a few extras for a multi-package corpus.
buildReference = (debugNames, targetPackages) -> (
    -- Make the doc-bearing packages visible in the CALLING context. The
    -- package-body needsPackage imports are private and rolled back when the
    -- package closes, so symbols like the Text hypertext types (DIV, HTML, ...)
    -- must be re-made-visible here or symbolForName drops them.
    needsPackage "Macaulay2Doc";
    needsPackage "JSON";
    needsPackage "Text";
    -- Load every target package so its dictionary, doc database, and symbols are
    -- live; null = no restriction (the original whole-runtime behaviour).
    targetPkgObjs := if targetPackages =!= null then apply(targetPackages, needsPackage);
    targetSet := if targetPackages =!= null then set targetPackages;
    targetPackagesByName := new MutableHashTable;
    if targetPackages =!= null then
        scan(#targetPackages, i -> targetPackagesByName#(targetPackages#i) = targetPkgObjs#i);
    -- Doc databases to consult. Core's docs live in Macaulay2Doc (always
    -- included); each other target package carries its own. Merge every entry
    -- into one key -> raw-source map -- a drop-in for a single package's database
    -- (db#key is the raw String, keys are the DocumentTag Format strings).
    docDbPackages := unique join({needsPackage "Macaulay2Doc"},
        if targetPkgObjs =!= null then targetPkgObjs else {});
    db := new MutableHashTable;
    scan(docDbPackages, p -> if p#?"raw documentation database" then (
        pdb := p#"raw documentation database";
        scan(keys pdb, k -> db#k = pdb#k)
    ));
    -- Candidate doc-source directories (Core's via Macaulay2Doc + each target's),
    -- consumed by resolveDocSourcePath in extractCommon to resolve relative
    -- doc filenames to absolute paths across packages.
    docSourceDirs = sort unique select(
        apply(docDbPackages, p -> if p#?"source directory" then p#"source directory"), d -> d =!= null);
    -- Runtime symbol resolution spans every target package's dictionary, with
    -- Core winning name ties (applied last); null targets keep Core as the sole
    -- dictionary, matching the original behaviour. symbolForName still falls back
    -- to getGlobalSymbol for names absent from these dictionaries.
    dictPackages := if targetPkgObjs =!= null then targetPkgObjs else {Core};
    runtimeDict := new MutableHashTable;
    scan(reverse dictPackages, p -> scan(keys p.Dictionary, k -> runtimeDict#k = (p.Dictionary)#k));
    -- A doc node names a package when its bare name is a target package (the
    -- package's own overview page, e.g. "Text"); for null targets keep just Core.
    isPackageNode := name -> if targetSet =!= null then targetSet#?name else name == "Core";
    -- A scoped package pass starts from that package's own dictionary. The
    -- global instance census is needed only for the legacy unscoped runtime
    -- pass; including it here made each package re-filter every symbol from all
    -- 301 preloaded packages.
    instanceNames := if targetSet === null
        then sort apply(keys instances Thing, toString)
        else {};
    operatorNames := sort apply(keys operatorAttributes, toString);
    visibleOperatorNames := if targetSet === null then operatorNames else
        select(operatorNames, name -> (
            sym := symbolForName(runtimeDict, name);
            sym =!= null and targetSet#?(packageForSymbol sym)
        ));
    packageNodeNames := if targetPackages =!= null then targetPackages else {"Core"};
    docEntriesByName := buildDocEntriesByName db;
    rawNames := sort unique join(
        packageNodeNames,
        join(
            instanceNames,
            join(
                apply(keys runtimeDict, toString),
                join(visibleOperatorNames, select(apply(keys db, recordNameFromDocKey),
                    name -> isPackageNode name
                    or runtimeDict#?name
                    or member(name, visibleOperatorNames)
                ))
            )
        )
    );
    includeReferenceName := name -> not match("^o[0-9]+$", name);
    -- Names are package-free. Core.Dictionary holds both the bare symbol and a
    -- `Core$`-qualified alias of it, so we debase every candidate to its bare
    -- name and dedup; the qualified form is preserved in each record's aliases.
    -- The package lives in its own field (see reference-schema.md).
    allNames := sort unique select(apply(rawNames, shortNameForRecordName), includeReferenceName);
    names := if #debugNames == 0 then allNames
        else sort unique select(apply(debugNames, shortNameForRecordName), includeReferenceName);
    -- In a package-scoped pass, discard names owned by other loaded packages
    -- before the type-hierarchy and record loops. The old late-only filter made
    -- every package repeatedly introspect all globally visible names; because
    -- packages accumulate in a multi-package run, each successive pass became
    -- more expensive even when the target package contained only a few records.
    if targetSet =!= null then
        names = select(names, name -> (
            sym := symbolForName(runtimeDict, name);
            isPackageNode name
            or (sym =!= null and targetSet#?(packageForSymbol sym))
        ));
    nameSet := set names;
    -- A single object can be bound to several global names (e.g. `indeterminate` and
    -- `NotANumber` are the *identical* value). Name-debasing only collapses `Core$x`
    -- onto `x`; it cannot see these. We keep just the record whose name is M2's
    -- canonical print form (`toString val`) and drop the others -- each is already
    -- listed in the keeper's aliases. A name is a droppable alias-dup when the print
    -- name is a *different* extracted name resolving to the *same* object.
    isAliasDuplicate := (val, name) -> (
        cp := try toString val;
        cp =!= null and cp =!= name and nameSet#?cp and (
            s2 := symbolForName(runtimeDict, cp);
            s2 =!= null and (valueForSymbol s2) === val
        )
    );
    (parentOf, ancestorsOf, childrenOf, instancesOf) := buildTypeHierarchy(names, runtimeDict);
    -- Generation timestamp, ISO 8601 UTC (schema's ISODateTime).
    nowIso := replace("[[:space:]]+$", "", get "!date -u +%Y-%m-%dT%H:%M:%SZ");
    records := apply(names, name -> (
        packageNode := isPackageNode name;
        sym := symbolForName(runtimeDict, name);
        if sym === null then
            return null;
        -- Keep the extractor's own exported tooling out of the runtime corpus.
        if (try package sym) === referencePackage then
            return null;
        -- Some legitimate packages do not expose a same-name symbol owned by
        -- their own dictionary (Complexes, MultiplierIdeals, Points,
        -- Regularity). For the package overview, use the Package object that
        -- needsPackage returned rather than the unrelated global binding.
        val := if packageNode and targetPackagesByName#?name
            then targetPackagesByName#name else valueForSymbol sym;
        if val === valueFailed then
            return null;
        -- Drop alias-duplicate names of the same object (keep the canonical print name).
        if isAliasDuplicate(val, name) then
            return null;
        className := safeClass val;
        kind := recordKind(sym, val, className, name);
        -- Don't document pure punctuation (syntax delimiters like ( ) [ ] { },
        -- and non-ASCII alias dupes). Real operators are punctuation too but carry
        -- semantics, so ASCII operators stay; a non-ASCII operator is kept only
        -- when it is a genuine symbol with no ASCII spelling (shouldExtractName /
        -- keepNonAscii), not an alias of an ASCII operator (·, ≠, ⊗, ...).
        if not (shouldExtractName(name) or (kind === "operator" and not hasNonAscii(name))) then
            return null;
        if targetSet =!= null and not packageNode
            and not targetSet#?(packageForSymbol sym) then
            return null;
        extracted := if kind === "methodFunction" then
            extractFunc(name, sym, val, db, docEntriesByName)
            else if kind === "function" then
            extractPlainFunction(name, sym, val, db, docEntriesByName)
            else if kind === "operator" then extractOperator(name, sym, val, db, docEntriesByName)
            else if kind === "type" then extractType(name, sym, val, db, docEntriesByName, parentOf, ancestorsOf, childrenOf, instancesOf)
            else if kind === "package" then extractPackage(name, sym, val, db, docEntriesByName)
            else if kind === "symbol" then extractSymbol(name, sym, val, db, docEntriesByName)
            else if kind === "table" then extractTable(name, sym, val, db, docEntriesByName)
            else extractObject(name, sym, val, db, docEntriesByName);
        rec := new MutableHashTable from extracted;
        if packageNode then (
            rec#PackageFun = referenceKey name;
            rec#AliasesFun = sort {
                name | "$" | name,
                "Package$" | name
            }
        );
        rec#DocEntriesFun = docEntriesForName(docEntriesByName, name);
        rec#LastUpdateFun = nowIso;
        rec
    ));
    present := select(records, r -> r =!= null);
    enrichCrossReferences present
)

-- Write the corpus as JSONL. Returns the number of records written.
-- Wall-clock the extraction (`elapsedTiming`, sub-second) and report aggregate
-- means: per package and per indexed unit, where a unit is a top-level record
-- OR a single method installation (methods are separate index entries, so they
-- are counted separately, not folded into their parent function).
writeObjectFacts = (outputPath, debugNames, targetPackages) -> (
    packageGroups := if targetPackages =!= null and #targetPackages > 1
        then apply(targetPackages, pkg -> {pkg})
        else {targetPackages};
    nPackages := #packageGroups;
    records := {};
    checkpointDir := try getenv "M2BOOK_CHECKPOINT_DIR";
    timed := elapsedTiming scan(#packageGroups, i -> (
        group := packageGroups#i;
        label := if group === null then "visible runtime" else first group;
        stderr << "-- [" << toString(i + 1) << "/" << toString nPackages
               << "] extracting package " << label << " ..." << endl << flush;
        packageTimed := elapsedTiming (packageRecords := buildReference(debugNames, group));
        packageMethods := sum apply(packageRecords,
            r -> if r#?MethodsFun then #(r#MethodsFun) else 0);
        records = join(records, packageRecords);
        -- A debug-name pass is a shard (currently Core), not a complete
        -- package. Only full package passes may publish package checkpoints.
        if #debugNames == 0 and checkpointDir =!= null and checkpointDir =!= "" then (
            checkpointPath := checkpointDir | "/" | label | ".jsonl";
            checkpointTemp := checkpointPath | ".tmp";
            checkpointOut := openOut checkpointTemp;
            scan(packageRecords, record ->
                checkpointOut << recordToJSON(new HashTable from record) << endl);
            close checkpointOut;
            moveFile(checkpointTemp, checkpointPath)
        );
        stderr << "-- [" << toString(i + 1) << "/" << toString nPackages
               << "] completed " << label << ": " << toString(#packageRecords)
               << " records + " << toString packageMethods << " method installs in "
               << toString(packageTimed#0) << "s" << endl << flush
    ));
    wallSeconds := timed#0;
    records = enrichCrossReferences records;
    out := openOut outputPath;
    scan(records, record -> out << recordToJSON(new HashTable from record) << endl);
    close out;
    nRecords := #records;
    nMethods := sum apply(records, r -> if r#?MethodsFun then #(r#MethodsFun) else 0);
    nUnits := nRecords + nMethods;
    stderr << "-- wrote " << toString nRecords << " records to " << outputPath << endl;
    stderr << "-- extraction timing (wall): " << toString wallSeconds << "s total" << endl;
    stderr << "--   " << toString nPackages << " package(s) -> "
           << toString(wallSeconds / nPackages) << "s/package (mean)" << endl;
    stderr << "--   " << toString nRecords << " records + " << toString nMethods
           << " method installs = " << toString nUnits << " units";
    if nUnits > 0 then
        stderr << " -> " << toString(wallSeconds / nUnits) << "s/unit (mean)";
    stderr << endl;
    nRecords
)

-- The packages a fresh session makes available: Core, the packages it preloads,
-- and the packages these export, transitively. Imported packages stay private.
freshSessionPackages = () -> (
    found := new MutableHashTable;
    visit := name -> if instance(name, String) and not found#?name then (
        found#name = true;
        scan((needsPackage name).Options.PackageExports ?? {}, visit));
    scan(prepend("Core", Core#"preloaded packages"), visit);
    sort keys found
)

-----------------------------------------------------------------------------
-- Facts about objects
-----------------------------------------------------------------------------

ObjectFacts = new Type of HashTable
ObjectFacts.synonym = "object facts"

-- The fields relating a record to the others extracted with it.
crossReferenceFields = {"constructors", "common_operations", "option_key_for"}
-- The fields an object's summary shows, in order.
summaryFields = {"name", "kind", "package", "class", "typical_value", "protected",
    "mutable", "option_passing"}

objectFactsOf = record -> new ObjectFacts from pairs jsonReady new HashTable from record

net ObjectFacts := facts -> netList(join(
    apply(select(summaryFields, field -> facts#?field and facts#field =!= null),
        field -> {field, net facts#field}),
    apply(select({"methods", "options"}, field -> facts#?field and #facts#field > 0),
        field -> {field, net(#facts#field) | " entries"})),
    Boxes => false, HorizontalSpace => 2)

-- The symbol naming an object: a symbol, a name, or a value with a global name.
factsSymbol = method(Dispatch => Thing)
factsSymbol Symbol := identity
factsSymbol String := name -> (
    if not isGlobalSymbol name then error("objectFacts: no global symbol ", name);
    getGlobalSymbol name)
factsSymbol Thing := x -> (
    name := toString x;
    if not isGlobalSymbol name or value getGlobalSymbol name =!= x then
        error("objectFacts: expected a symbol, a name or a named object");
    getGlobalSymbol name)

objectFacts = method(Dispatch => Thing, TypicalValue => ObjectFacts)
objectFacts Thing := key -> (
    sym := factsSymbol key;
    name := toString sym;
    pkgname := packageForSymbol sym;
    if pkgname === null then error("objectFacts: ", name, " belongs to no package");
    records := select(buildReference({name}, {pkgname}), record -> record#NameFun === name);
    if #records == 0 then error("objectFacts: no facts recorded for ", name);
    facts := objectFactsOf first records;
    -- extracted alone, an object has no others to relate to: unknown, not none
    new ObjectFacts from merge(facts,
        hashTable apply(select(crossReferenceFields, field -> facts#?field), field -> field => null),
        last)
)

packageObjectFacts = method(TypicalValue => List)
packageObjectFacts String := name -> apply(buildReference({}, {name}), objectFactsOf)
packageObjectFacts Package := pkg -> packageObjectFacts pkg#"pkgname"

-----------------------------------------------------------------------------
-- The m2-ls index
-----------------------------------------------------------------------------

writeLSPIndex = method(Options => {Names => {}})
writeLSPIndex (String, List) := ZZ => opts -> (filename, packages) -> (
    if #packages == 0 or not all(packages, name -> instance(name, String)) then
        error "writeLSPIndex: expected a nonempty list of package names";
    if not instance(opts.Names, List) or not all(opts.Names, name -> instance(name, String)) then
        error "writeLSPIndex: expected Names to be a list of strings";
    work := temporaryFileName();
    makeDirectory work;
    facts := work | "/facts.jsonl";
    writeObjectFacts(facts, opts.Names, packages);
    writeReferencePages(facts, work | "/pages");
    count := assembleReference(work | "/pages", facts, work | "/reference.jsonl",
        filename, freshSessionPackages());
    if run("rm -rf -- " | shellQuote work) != 0 then
        error("writeLSPIndex: could not remove ", work);
    count
)
