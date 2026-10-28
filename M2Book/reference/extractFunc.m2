
-- ---------------------------------------------------------------------------
-- Signature helpers. `methods f` returns a NumberedVerticalList of
-- Sequence values; each Sequence is `(name, ...domain-types)`. We convert
-- to a list of strings for hashing and JSON.
-- ---------------------------------------------------------------------------

signatureItems = sig -> if instance(sig, Sequence) then apply(toList sig, item -> toString item) else {toString sig}

methodDomainFromSignature = signature -> (
    if #signature <= 1 then
        {}
    else
        apply(drop(signature, 1), referenceKey)
)

methodNormalizedName = signature -> (
    methodName := if #signature == 0 then "" else first signature;
    domain := methodDomainFromSignature signature;
    normalizedNameForRecordName(methodName) | "(" | demark(",", domain) | ")"
)

-- ---------------------------------------------------------------------------
-- Codomain extraction from per-installation doc entries.
-- The raw doc-node string for a method installation contains an `Outputs`
-- block whose first TO2/DocumentTag names the return type.
-- Pattern: Outputs => { ... TO2{new DocumentTag from {"TypeName",...} ...}
-- We extract the first TypeName after the Outputs key.
-- ---------------------------------------------------------------------------

codomainFromDocRaw = raw -> (
    if instance(raw, String) then
        if #raw != 0 then (
        outputsMatch := try regex("Outputs\\s*=>", raw);
        if outputsMatch =!= null and instance(outputsMatch, BasicList) then (
            if #outputsMatch > 0 then (
                tail := substring(outputsMatch#0#0, #raw, raw);
                tagMatch := try regex("DocumentTag from \\{\"([^\"]+)\"", tail);
                if tagMatch =!= null and instance(tagMatch, BasicList) then (
                    if #tagMatch > 1 then
                        substring(tagMatch#1#0, tagMatch#1#1, tail)
                )
            )
        )
    )
)

codomainForMethod = (methodKey, entriesByName) -> (
    baseName := first separate("\\(", methodKey);
    docEntries := entriesByName#(shortNameForRecordName(baseName)) ?? {};
    result := null;
    scan(docEntries, e -> (
        if e#KeyFun == methodKey and e#?RawFun and instance(e#RawFun, String) then (
            raw := e#RawFun;
            codomain := codomainFromDocRaw raw;
            if codomain =!= null and codomain =!= "" then
                result = codomain;
        )
    ));
    result
)

-- ---------------------------------------------------------------------------
-- Per-installation record. The v2 schema's `MethodDoc` extends
-- `CommonObjectDoc`, so each installation carries a subset of the base
-- fields plus method-specific ones. The full base field set is not
-- meaningful per-installation (no separate `last_update`, no separate
-- `v_added`); we carry the fields that are.
--
-- The codomain field is left null for now. M2 has no per-method return
-- type at runtime; the function-level `TypicalValue` is the closest
-- approximation and lives on the parent function. The plan note
-- `M2 Introspection Methods.md` flags this gap.
-- ---------------------------------------------------------------------------

-- A method installation: the shared method-level base specialised by domain and
-- typical value, plus any brief/description/examples specific to this method.
-- typicalValue is null when typicalValues has no concrete type (Thing excluded).
methodRecord = (signature, packageKey, typicalValue, brief, description, examples, sourceLoc) -> (
    installationName := methodNormalizedName signature;
    installationNormalized := normalizeName installationName;
    rec := new MutableHashTable from methodBaseRecord(
        installationName, installationNormalized, packageKey,
        methodDomainFromSignature signature, typicalValue
    );
    rec#BriefFun = brief;
    rec#DescriptionFun = description;
    rec#ExamplesFun = examples;
    rec#SourceLocationFun = sourceLoc;
    rec#SourceFun = sourceTextFor sourceLoc;
    new HashTable from rec
)

methodHasOwnDocumentation = (signature, entriesByName) -> (
    items := signatureItems signature;
    methodKey := methodNormalizedName items;
    baseName := if #items > 0 then first items else "";
    any(docEntriesForName(entriesByName, baseName), entry -> (
        key := toString entry#KeyFun;
        key === methodKey or last separate("::", key) === methodKey
    ))
)

-- `methodSource` is whatever `methods` should be queried on: the function value
-- for functions, the operator symbol for operators (`methods symbol +`).
methodRecords = (methodSource, sym, entriesByName) -> (
    ms := try methods methodSource;
    if ms === null or length ms == 0 then
        {}
    else (
        pkg := if sym =!= null then referenceKey(packageForSymbol sym);
        -- The function-level doc, to keep only the method content that differs
        -- from it (M2 falls back to the function doc for undocumented methods).
        fnH := if sym =!= null then helpForRecord(sym, toString sym);
        fb := briefFromHelp fnH;
        fd := descriptionFromHelp fnH;
        fe := examplesFromHelp fnH;
        apply(0..(length ms - 1), i -> (
            sig := ms#i;
            tv := if typicalValues#?sig and typicalValues#sig =!= Thing then referenceKey typicalValues#sig;
            -- An undocumented installation inherits the parent help verbatim,
            -- so asking M2 to render it only to compare equal fields is wasted.
            mh := if methodHasOwnDocumentation(sig, entriesByName)
                then helpForInstallation(sym, sig)
                else fnH;
            mb := briefFromHelp mh;
            md := descriptionFromHelp mh;
            me := examplesFromHelp mh;
            methodRecord(signatureItems(sig), pkg, tv,
                if toString mb != toString fb then mb,
                if md != fd then md else "",
                if toString me != toString fe then
                    me
                else
                    {},
                methodSourceLocation sig
            )
        ))
    )
)

-- ---------------------------------------------------------------------------
-- Options. `methodOptions f` returns the option table the function was
-- created with; `Options` is the list of `[name, default]` pairs.
-- `TypicalValue` (capital T in M2) is the function-level return-type hint.
-- ---------------------------------------------------------------------------

-- TypicalValue `Thing` is the universal type -- it conveys no return-type
-- information, so treat it as no typical value (null) rather than recording it.
typicalValueRecord = value -> (
    optionTable := try methodOptions value;
    if optionTable =!= null and optionTable#?TypicalValue and optionTable#TypicalValue =!= Thing then
        referenceKey(optionTable#TypicalValue)
)

-- An option record. The default comes from the runtime option table; the
-- description is the headline of the option's own doc page (parsed from the raw
-- doc block), which the rendered function help does not surface.
optionEntry = (opt, db, funcName) -> (
    if instance(opt, Option) or instance(opt, Sequence) then (
        optName := toString first opt;
        hashTable {
            KeyFun => referenceKey(optName),
            DefaultFun => safeString last opt,
            ValueTypeFun => null,
            DescriptionFun => optionDocHeadline(db, funcName, optName) ?? "",
            PossibleValuesFun => {}
        }
    )
)

optionRecords = (opts, db, funcName) -> (
    if opts === null then
        {}
    else (
        entries := if instance(opts, OptionTable) then pairs opts
            else if instance(opts, BasicList) then pairs opts
            else {};
        select(apply(entries, opt -> optionEntry(last opt, db, funcName)), e -> e =!= null)
    )
)

methodOptionRecords = (value, db, funcName) -> (
    optionTable := try methodOptions value;
    opts := if optionTable =!= null and optionTable#?Options then optionTable#Options;
    optionRecords(opts, db, funcName)
)

-- ---------------------------------------------------------------------------
-- MethodFunctionDoc extension (kind "methodFunction"). Merged on top of the
-- CommonObjectDoc base, which already set kind from `recordKind`, so the
-- "kind" here is only a default for the dispatcher and is ignored by
-- fillMissingFields. Only method functions carry a `methods` array (their
-- per-domain installations) and `methodOptions`-derived options.
-- ---------------------------------------------------------------------------

funcExtras = (name, value, sym, db, entriesByName) -> (
    h := helpForRecord(sym, name);
    rec := new MutableHashTable from {
        KindFun => "methodFunction",
        TypicalValueFieldFun => typicalValueRecord(value),
        DomainDescriptionFun => domainDescriptionFromHelp h,
        CodomainDescriptionFun => codomainDescriptionFromHelp h,
        MethodsFun => {},
        OptionsFun => {}
    };
    methods := methodRecords(value, sym, entriesByName);
    if #methods > 0 then
        rec#MethodsFun = methods;
    options := methodOptionRecords(value, db, name);
    if #options > 0 then
        rec#OptionsFun = options;
    new HashTable from rec
)

extractFunc = (name, sym, value, db, entriesByName) -> fillMissingFields(
    extractCommon(name, sym, value, db, entriesByName),
    funcExtras(name, value, sym, db, entriesByName)
)

-- ---------------------------------------------------------------------------
-- Plain FunctionDoc extension (kind "function"). A FunctionClosure /
-- CompiledFunction / Command / Manipulator / ScriptedFunctor has a single
-- body and supports NO method installation, so it carries no `methods` array.
-- Its return type, when M2 records one, lives in `typicalValues#value` (the
-- function value itself as key); `methodOptions`/`typicalValueRecord` ERROR on
-- non-method functions, so they are not used here. Options, when the closure
-- was built with them, come from the user-visible `options value` table.
-- ---------------------------------------------------------------------------

plainTypicalValue = value -> (
    if typicalValues#?value and typicalValues#value =!= Thing then
        referenceKey typicalValues#value
)

plainOptionRecords = (value, db, funcName) -> optionRecords(try options value, db, funcName)

-- Compiled builtins have no source body and usually expose no entry through
-- `methods`, so M2 cannot report their static call signature. Keep the small
-- set of signatures that are part of the language contract explicit here.
-- These records feed the LSP's callable-signature transport; they are not
-- per-domain M2 method installations.
curatedPlainSignatures = hashTable {
    "Core$protect" => {
        hashTable {
            DomainFun => {"Symbol"},
            TypicalValueFun => "Symbol",
            ExactFun => true
        }
    }
}

curatedPlainSignatureRecords = (name, sym) -> (
    packageName := packageForSymbol sym;
    key := if packageName =!= null then packageName | "$" | name else name;
    specs := curatedPlainSignatures#key ?? {};
    apply(specs, spec -> (
        rec := new MutableHashTable from methodRecord(
            prepend(name, spec#DomainFun),
            referenceKey packageName,
            referenceKey(spec#TypicalValueFun),
            "", "", {}, null
        );
        rec#ExactFun = spec#ExactFun;
        new HashTable from rec
    ))
)

plainFuncExtras = (name, value, sym, db, entriesByName) -> (
    h := helpForRecord(sym, name);
    rec := new MutableHashTable from {
        KindFun => "function",
        TypicalValueFieldFun => plainTypicalValue value,
        DomainDescriptionFun => domainDescriptionFromHelp h,
        CodomainDescriptionFun => codomainDescriptionFromHelp h,
        MethodsFun => {},
        OptionsFun => {}
    };
    -- A plain function is not method-overloadable, but `methods value` still
    -- reports its call signature(s) (static dispatch). One entry IS the function's
    -- signature; several reflect installed methods. We list them either way.
    methods := methodRecords(value, sym, entriesByName);
    if #methods == 0 then
        methods = curatedPlainSignatureRecords(name, sym);
    if #methods > 0 then
        rec#MethodsFun = methods;
    options := plainOptionRecords(value, db, name);
    if #options > 0 then
        rec#OptionsFun = options;
    new HashTable from rec
)

extractPlainFunction = (name, sym, value, db, entriesByName) -> fillMissingFields(
    extractCommon(name, sym, value, db, entriesByName),
    plainFuncExtras(name, value, sym, db, entriesByName)
)
