-- One persistent full-runtime worker for scripts/extract_all_packages.sh.
-- It extracts an interleaved package batch and a disjoint Core name shard after
-- a single preload. Full package records are checkpointed by writeReferenceJSON;
-- the Core shard is written only when that shard completes.
--
-- Usage:
--   M2 --script scripts/extract_all_packages_worker.m2 \
--      package-output packages-csv core-names-file core-output
-- A dash disables the corresponding package or Core phase.

load "./load_package.m2"

args := drop(scriptCommandLine, 1);
if #args != 4 then
    error "expected package-output packages-csv core-names-file core-output";

packageOutput := args#0;
packagesCSV := args#1;
coreNamesFile := args#2;
coreOutput := args#3;

allPackages := standardPackageNames();
stderr << "-- preloading " << toString(#allPackages)
       << " packages before extraction ..." << endl << flush;
preloadTimed := elapsedTiming scan(allPackages, needsPackage);
stderr << "-- preloaded " << toString(#allPackages) << " packages in "
       << toString(preloadTimed#0) << "s" << endl << flush;

if packagesCSV =!= "-" then (
    targetPackages := select(separate(",", packagesCSV), pkg -> #pkg > 0);
    if #targetPackages > 0 then
        writeReferenceJSON(packageOutput, {}, targetPackages)
);

if coreNamesFile =!= "-" then (
    coreNames := select(lines get coreNamesFile, name -> #name > 0);
    if #coreNames > 0 then
        writeReferenceJSON(coreOutput, coreNames, {"Core"})
);

exit 0
