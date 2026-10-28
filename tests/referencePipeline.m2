-- Runtime facts through extraction, Markdown rendering and the LSP index.
--
-- Usage:
--   M2 --script tests/referencePipeline.m2

load "./harness.m2"

-- Whether a text contains another literally.
containsText = (text, part) -> any(0 .. #text - #part, i -> substring(i, #part, text) == part)

-- The facts of names of a package, extracted into a scratch directory.
extractFacts = (dir, package, names) -> (
    facts := dir | "/facts.jsonl";
    succeeds(runScript("extract_m2_facts.m2", join({facts, "packages=" | package}, names)),
        "extraction");
    facts)

-- The reference pages and the LSP index of a facts file; the index records.
assembleIndex = (dir, facts) -> (
    succeeds(runScript("render_markdown.m2", {facts, dir | "/pages"}), "rendering");
    succeeds(runScript("assemble_jsonl.m2",
        {dir | "/pages", facts, dir | "/reference.jsonl", dir | "/index.jsonl"}), "assembly");
    readRecords(dir | "/index.jsonl"))

optionNamed = (options, key) -> first select(options, option -> option#"key" == key)

testCase("a variable is not taken for an alias of its value", () -> (
    -- lastMatch is null before any match, the value of the symbol null
    result := runScript("list_package_reference_names.m2", {"Core"});
    succeeds(result, "listing the names of Core");
    names := set lines result#"stdout";
    expect(names#?"lastMatch" and names#?"null", "both lastMatch and null listed", result);
    -- extracted together with the constants their values print as
    dir := scratchDirectory "m2book-variables";
    variables := {"lastMatch", "debuggingMode", "notify", "backtrace"};
    facts := recordsByName readRecords extractFacts(dir, "Core", join({"true", "false", "null"}, variables));
    scan(variables, name -> expect(facts#?name, "a record of the variable " | name, null));
    -- a constant still keeps a single record for its other names
    aliases := recordsByName readRecords extractFacts(dir, "Core", {"indeterminate", "NotANumber"});
    expect(#aliases == 1, "one record for indeterminate and NotANumber", null);
    removeScratch dir))

testCase("invalid source spans are recovered", () -> (
    dir := scratchDirectory "m2book-sources";
    facts := dir | "/facts.jsonl";
    enriched := dir | "/enriched.jsonl";
    invalid := hashTable {"filename" => "unavailable", "start_row" => "not a row",
        "start_col" => 0, "stop_row" => 1, "stop_col" => 0};
    generated := hashTable {"filename" => "currentString", "start_row" => 1,
        "start_col" => 0, "stop_row" => 1, "stop_col" => 5};
    facts << toJSON hashTable {"name" => "pi", "package" => "Core",
            "source_location" => invalid, "source" => "invalid",
            "methods" => {
                hashTable {"source_location" => invalid, "source" => "invalid"},
                hashTable {"source_location" => generated, "source" => null}}} << "\n"
        << toJSON hashTable {"name" => "missingObject",
            "package" => "UnavailableReferenceSourcePackage"} << "\n" << close;
    result := runScript("enrich_sources.m2", {facts, enriched});
    succeeds(result, "source enrichment");
    (record, missing) := toSequence readRecords enriched;
    expect(instance(record#"source_location"#"start_row", ZZ), "a numeric start row", result);
    expect(match("^/", record#"source_location"#"filename"), "an absolute filename", result);
    expect(record#"source" =!= "invalid", "the source read again", result);
    expect(record#"methods"#0#"source_location" === null, "an invalid method span dropped", result);
    expect(record#"methods"#0#"source" === null, "its source dropped", result);
    expect(record#"methods"#1#"source_location" === null, "a generated span dropped", result);
    expect(missing#"name" == "missingObject", "the record of a missing package kept", result);
    expect(missing#"source_location" === null and missing#"source" === null,
        "no source for it", result);
    removeScratch dir))

testCase("source locations skip Core's wrappers", () -> (
    dir := scratchDirectory "m2book-locations";
    facts := recordsByName readRecords extractFacts(dir, "Core",
        {"End", "method", "errorDepth", "ascii", "+"});
    -- functions with options are located at their body, not at Core's wrapper
    expect(match("/Hom\\.m2$", facts#"End"#"source_location"#"filename"), "End in Hom.m2", null);
    expect(containsText(facts#"End"#"source", "End ="), "the definition of End", null);
    expect(containsText(facts#"method"#"source", "method ="), "the definition of method", null);
    -- an integer value is not an index into the last `methods` listing
    errorDepth := facts#"errorDepth";
    expect(errorDepth#"source_location" === null or containsText(errorDepth#"source", "errorDepth"),
        "no unrelated location for errorDepth", null);
    -- typical-value declarations on a compiled function have no definition
    expect(#facts#"ascii"#"methods" > 0, "methods of ascii", null);
    scan(facts#"ascii"#"methods", installation ->
        expect(installation#"source_location" === null, "no location for ascii's methods", null));
    -- nor do those Core installs on keywords; real operator methods keep theirs
    plusFiles := apply(select(facts#"+"#"methods", installation ->
        installation#"source_location" =!= null), installation -> installation#"source_location"#"filename");
    expect(#plusFiles > 0, "located methods of +", null);
    expect(not any(plusFiles, filename -> match("/m2/typicalvalues\\.m2$", filename)),
        "no method of + located at a typical-value declaration", null);
    removeScratch dir))

testCase("options survive the pipeline", () -> (
    dir := scratchDirectory "m2book-options";
    facts := extractFacts(dir, "Core", {"End", "gb", "degree", "isPrime", "ZZ", "Nothing"});
    byName := recordsByName readRecords facts;
    scan({("End", "table"), ("gb", "table"), ("degree", "absent"), ("isPrime", "forwarded")},
        (name, passing) -> expect(byName#name#"option_passing" == passing,
            name | " taking options as " | passing, null));
    degreeLimit := optionNamed(byName#"End"#"options", "DegreeLimit");
    expect(degreeLimit#"valueType" == "ZZ", "the documented type of DegreeLimit", null);
    expect(degreeLimit#"defaultType" == "Nothing", "the class of its default", null);
    compiled := recordsByName drop(assembleIndex(dir, facts), 1);
    end := compiled#"End";
    expect(end#"option_passing" == "table", "option passing in the index", null);
    expect(containsText(end#"markdown", "**Options accepted:**"), "option passing on the page", null);
    degreeLimit = optionNamed(end#"options", "DegreeLimit");
    expect(degreeLimit#"valueType" == "$Core$ZZ", "the documented type as a reference", null);
    expect(degreeLimit#"defaultType" == "$Core$Nothing", "the default class as a reference", null);
    -- every field the index carries is declared by its schema
    definitions := (fromJSON get(repositoryRoot | "m2-index.schema.json"))#"$defs";
    declared := name -> set keys definitions#name#"properties";
    declaredFields := (table, name, owner) -> expect(isSubset(set keys table, declared name),
        "the fields of " | owner | " declared by " | name, null);
    scan(values compiled, record -> (
        declaredFields(record, "CompiledObject", record#"name");
        scan(record#"options" ?? {}, option -> declaredFields(option, "CompiledOption", record#"name"));
        scan(record#"methods" ?? {}, installation -> (
            declaredFields(installation, "CompiledMethod", record#"name");
            scan(installation#"options" ?? {}, option ->
                declaredFields(option, "CompiledOption", record#"name"))))));
    removeScratch dir))

testCase("mutability and signatures survive the pipeline", () -> (
    dir := scratchDirectory "m2book-reference";
    names := {"ZZ", "Type", "allowableThreads", "pi", "path", "degree"};
    facts := extractFacts(dir, "Core", names);
    records := readRecords facts;
    byName := recordsByName records;
    expect(set keys byName === set names, "a record for each name", null);
    scan({("ZZ", false, true), ("Type", false, true), ("allowableThreads", true, false),
            ("pi", false, true), ("path", true, false)},
        (name, mutable, protected) -> (
            expect(byName#name#"mutable" === mutable, name | " mutable: " | toString mutable, null);
            expect(byName#name#"protected" === protected, name | " protected: " | toString protected, null)));
    expect(#byName#"degree"#"methods" > 0, "methods of degree", null);
    methodSources := select(byName#"degree"#"methods", installation ->
        installation#"source_location" =!= null and installation#"source" =!= null);
    expect(#methodSources > 0, "located methods of degree", null);
    -- unknown runtime queries must stay unknown in the projected corpus
    records = apply(records, record -> if record#"name" == "path"
        then merge(record, hashTable {"mutable" => null}, last) else record);
    byName = recordsByName records;
    facts << concatenate apply(records, record -> toJSON record | "\n") << close;
    compiled := assembleIndex(dir, facts);
    expect((first compiled)#"kind" == "meta", "a leading meta record", null);
    baselineScript := dir | "/baseline.m2";
    baselineScript << "scan(sort apply(loadedPackages, toString), print); exit 0\n" << close;
    baseline := runCommand(demark(" ", apply({m2Executable, "--script", baselineScript}, shellQuote)),
        hashTable {}, "");
    succeeds(baseline, "listing a fresh session's packages");
    expect((first compiled)#"default_loaded" == lines baseline#"stdout",
        "the packages of a fresh session", baseline);
    expect(#compiled == #records + 1, "a record for each fact", null);
    result := recordsByName drop(compiled, 1);
    scan(pairs byName, (name, record) -> (
        scan({"mutable", "protected", "source_location", "source"}, field ->
            expect(result#name#field === record#field, name | " keeping " | field, null));
        before := record#"methods" ?? {};
        after := result#name#"methods" ?? {};
        expect(#after == #before, name | " keeping its methods", null);
        scan(#before, i -> scan({"source_location", "source"}, field ->
            expect(after#i#field === before#i#field, name | " keeping the " | field | " of its methods", null)))));
    scan({("ZZ", "**Mutable:** false"), ("Type", "**Mutable:** false"),
            ("allowableThreads", "**Mutable:** true"), ("pi", "**Mutable:** false"),
            ("path", "**Protected:** false"), ("degree", "**Defined at:**"),
            ("degree", "#### Source"), ("degree", methodSources#0#"source")},
        (name, text) -> expect(containsText(result#name#"markdown", text), name | " showing " | text, null));
    expect(not containsText(result#"path"#"markdown", "**Mutable:**"), "an unknown fact not shown", null);
    scan(readRecords(dir | "/reference.jsonl"), record -> scan(record#"methods" ?? {}, installation ->
        expect(not containsText(installation#"description" ?? "", "#### Source"),
            "no source heading in a method description", null)));
    removeScratch dir))
