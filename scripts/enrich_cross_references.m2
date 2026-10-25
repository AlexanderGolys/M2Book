-- Recompute corpus-wide type and option-key cross references after independently
-- extracted package batches have been concatenated.
--
-- Usage:
--   M2 --script scripts/enrich_cross_references.m2 input.jsonl output.jsonl

needsPackage "JSON"

args := drop(scriptCommandLine, 1);
inputPath := if #args > 0 then args#0 else "m2-facts.jsonl";
outputPath := if #args > 1 then args#1 else inputPath | ".enriched";

records := select(
    apply(lines get inputPath, line -> if #line == 0 then null else fromJSON line),
    rec -> rec =!= null);

-- Parallel extraction concatenates worker shards. Restore deterministic package
-- order (the order in which packages first appear) and normalized-name order
-- within each package before enriching and writing the final corpus.
packageOrder := new MutableHashTable;
nextPackageIndex := 0;
scan(records, rec -> (
    packageName := if rec#?"package" and rec#"package" =!= null
        then toString rec#"package" else "Core";
    if not packageOrder#?packageName then (
        packageOrder#packageName = nextPackageIndex;
        nextPackageIndex = nextPackageIndex + 1
    )
));
records = apply(sort apply(#records, i -> (
    rec := records#i;
    packageName := if rec#?"package" and rec#"package" =!= null
        then toString rec#"package" else "Core";
    normalized := if rec#?"normalized_name" and rec#"normalized_name" =!= null
        then ascii toString rec#"normalized_name" else {};
    (packageOrder#packageName, normalized, i, rec)
)), item -> item#3);

recordsByName := new MutableHashTable;
scan(records, rec ->
    if rec#?"name" and rec#"name" =!= null then
        recordsByName#(toString rec#"name") = rec);

constructorsForType := new MutableHashTable;
commonOpsForType := new MutableHashTable;
optionKeyFor := new MutableHashTable;

scan(keys recordsByName, name -> (
    rec := recordsByName#name;
    kind := if rec#?"kind" then rec#"kind";
    if kind === "function" or kind === "methodFunction" then (
        funcNorm := rec#"normalized_name";
        tv := if rec#?"typical_value" then rec#"typical_value";
        if tv =!= null then
            constructorsForType#tv = append(constructorsForType#tv ?? {}, funcNorm);
        methods := if rec#?"methods" then rec#"methods" else {};
        scan(methods, method -> (
            domain := if method#?"domain" then method#"domain" else {};
            scan(domain, typeName ->
                commonOpsForType#typeName =
                    append(commonOpsForType#typeName ?? {}, funcNorm))
        ));
        options := join(
            if rec#?"options" then rec#"options" else {},
            flatten apply(methods,
                method -> if method#?"options" then method#"options" else {}));
        scan(options, option -> if option#?"key" then (
            key := option#"key";
            optionKeyFor#key = append(optionKeyFor#key ?? {}, funcNorm)
        ))
    )
));

enriched := apply(records, rec0 -> (
    rec := new MutableHashTable from rec0;
    kind := if rec#?"kind" then rec#"kind";
    if kind === "type" then (
        typeNorm := rec#"normalized_name";
        typeName := rec#"name";
        rec#"constructors" = sort unique join(
            sort unique(constructorsForType#typeNorm ?? {}),
            sort unique(constructorsForType#typeName ?? {}));
        rec#"common_operations" = sort unique join(
            sort unique(commonOpsForType#typeNorm ?? {}),
            sort unique(commonOpsForType#typeName ?? {}))
    );
    if kind === "symbol" then (
        symbolNorm := rec#"normalized_name";
        symbolName := rec#"name";
        rec#"option_key_for" = sort unique join(
            sort unique(optionKeyFor#symbolNorm ?? {}),
            sort unique(optionKeyFor#symbolName ?? {}))
    );
    new HashTable from rec
));

out := openOut outputPath;
scan(enriched, rec -> out << toJSON rec << endl);
close out;
stderr << "-- enriched cross references for " << toString(#enriched)
       << " records -> " << outputPath << endl;
exit 0
