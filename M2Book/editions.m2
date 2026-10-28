-- Only edited pages and assets belong in the repository. Each curated build
-- starts from the current renderer and overlays those files in a separate tree.
sourceRepository = toAbsolutePath(currentFileDirectory | "../")
shellQuote = s -> "'" | replace("'", "'\\\\''", s) | "'"

writeCuratedM2Book = method(Options => options writeM2Book)
writeCuratedM2Book (String, String, String) := String => opts -> (name, dir, repository) -> (
    repository = toAbsolutePath repository;
    if not fileExists(repository | "/M2Book.m2")
        or not isDirectory(repository | "/curated") then
        error "M2Book: provide the repository containing M2Book.m2 and curated/";
    destination := toAbsolutePath(dir | "/" | name);
    curatedRoot := repository | "/curated/";
    if substring(0, #curatedRoot, destination | "/") === curatedRoot then
        error "M2Book: build outside curated/ to preserve the edited sources";
    overrides := repository | "/curated/" | name;
    bookDir := writeBookFiles(writeM2Book(name, dir, opts),
        BookTitle => name | " — Curated");
    if isDirectory overrides then (
        if run("cp -R -- " | shellQuote(overrides | "/.") | " " | shellQuote bookDir) != 0 then
            error("M2Book: could not apply curated files from ", overrides));
    bookDir
)
writeCuratedM2Book (String, String) := String => opts -> (name, dir) ->
    writeCuratedM2Book(name, dir, sourceRepository, opts)
