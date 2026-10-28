-- Thin CLI shim over the M2Book package. All orchestration lives in
-- ../M2Book.m2; this file only parses arguments and delegates, so the
-- extractor's helper functions stay private (no self-pollution of the corpus).
--
-- Usage:
--   M2 --script scripts/extract_m2_facts.m2 [out.jsonl] [packages=<list>] [name1 ...]
-- With no names, extracts every visible symbol. `packages=<comma-list>` (any
-- position, repeatable) restricts the corpus to those packages; the token
-- `default` expands to the packages M2 loads on a fresh start (Core + transitive
-- deps), while `all` expands to Core plus every package entry point on M2's
-- standard package path. `package=<name>` (singular) is the legacy single-package
-- form. With no package argument, every visible symbol is extracted. Examples:
--   packages=Core                      -- the core corpus
--   packages=default,Text,JSON         -- default-loaded set plus two extras
--   packages=all                       -- every standard package, with progress

-- Capture the default-loaded baseline BEFORE M2Book pulls in extra packages, so
-- the `default` token expands to exactly the fresh-start set (and not Text/JSON
-- that M2Book imports for its own rendering).
defaultLoadedPackages := sort apply(loadedPackages, toString)

load "./load_package.m2"

-- Use := (file-local) so these never become documented User globals.
scriptArgs := drop(scriptCommandLine, 1)
expandPackageToken := tok -> (
    if tok == "default" then defaultLoadedPackages
    else if tok == "all" then standardPackageNames()
    else {tok});
pluralArgs := select(scriptArgs, a -> match("^packages=", a));
singularArgs := select(scriptArgs, a -> match("^package=", a));
preloadArgs := select(scriptArgs, a -> match("^preload=", a));
nameFileArgs := select(scriptArgs, a -> match("^names_file=", a));
positional := select(scriptArgs,
    a -> not match("^packages?=", a)
        and not match("^preload=", a)
        and not match("^names_file=", a));
fromPlural := flatten apply(pluralArgs, a ->
    flatten apply(separate(",", substring(a, 9)), expandPackageToken));
fromSingular := apply(singularArgs, a -> substring(a, 8));
selected := sort unique select(join(fromPlural, fromSingular), s -> #s > 0);
targetPackages := if #selected > 0 then selected;
preloadPackages := sort unique flatten apply(preloadArgs, a ->
    flatten apply(separate(",", substring(a, 8)), expandPackageToken));
outputPath := if #positional > 0 then positional#0 else "m2-facts.jsonl";
debugNames := join(
    if #positional > 1 then drop(positional, 1) else {},
    flatten apply(nameFileArgs, arg ->
        select(lines get substring(arg, 11), line -> #line > 0)));

if #preloadPackages > 0 then (
    stderr << "-- preloading " << toString(#preloadPackages)
           << " packages before extraction ..." << endl << flush;
    preloadTimed := elapsedTiming scan(preloadPackages, needsPackage);
    stderr << "-- preloaded " << toString(#preloadPackages) << " packages in "
           << toString(preloadTimed#0) << "s" << endl << flush
);

writeReferenceJSON(outputPath, debugNames, targetPackages)
exit 0
