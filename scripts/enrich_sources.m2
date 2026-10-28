-- Complete and normalize source metadata after combining package checkpoints.
-- Usage: M2 --script scripts/enrich_sources.m2 input.jsonl output.jsonl [preload=all]

load "./load_package.m2"
needsPackage "JSON"
importFrom("M2Book", {"sourceLocationFor", "sourceTextFor", "sourceFilePath", "jsonReady"})

args := drop(scriptCommandLine, 1);
if #args < 2 or #args > 3 or (#args == 3 and args#2 =!= "preload=all") then
    error "expected input.jsonl output.jsonl [preload=all]";
records := select(apply(lines get args#0,
    line -> if #line > 0 then fromJSON line), record -> record =!= null);

-- Match the full-runtime extraction context, including cross-package methods.
packages := sort unique apply(records, record -> record#"package");
sourcePackages := new MutableHashTable;
scan(if #args == 3 then standardPackageNames() else packages, name -> (
    sourcePackages#name = try needsPackage name;
    if sourcePackages#name === null then
        stderr << "-- declaration lookup unavailable for package " << name << endl
));

normalizeLocation := location -> (
    if not instance(location, HashTable) then return null;
    coordinates := {"start_row", "start_col", "stop_row", "stop_col"};
    if not all(coordinates, key -> location#?key and instance(location#key, ZZ)) then return null;
    if location#"start_row" < 1 or location#"stop_row" < location#"start_row"
        or location#"start_col" < 0 or location#"stop_col" < 0 then return null;
    if location#"start_row" == location#"stop_row"
        and location#"stop_col" < location#"start_col" then return null;
    if not location#?"filename" or not instance(location#"filename", String) then return null;
    result := new MutableHashTable from location;
    result#"filename" = sourceFilePath result#"filename";
    if result#"filename" === null then return null;
    new HashTable from result
);

completeSource := (record, sym) -> (
    result := new MutableHashTable from record;
    location := normalizeLocation(result#"source_location" ?? null);
    if location === null then result#"source" = null;
    if location === null and sym =!= null then (
        span := sourceLocationFor sym;
        if span =!= null then (
            location = jsonReady span;
            result#"source" = sourceTextFor span
        )
    );
    result#"source_location" = normalizeLocation location;
    new HashTable from result
);

out := openOut args#1;
scan(records, record -> (
    packageName := record#"package";
    if not sourcePackages#?packageName then
        sourcePackages#packageName = try needsPackage packageName;
    pkg := sourcePackages#packageName;
    name := record#"name";
    sym := if pkg =!= null and pkg.Dictionary#?name then pkg.Dictionary#name;
    result := new MutableHashTable from completeSource(record, sym);
    if result#?"methods" then
        result#"methods" = apply(result#"methods", method -> completeSource(method, null));
    out << toJSON(new HashTable from result) << endl
));
close out;
stderr << "-- completed source metadata for " << #records << " records" << endl;
exit 0
