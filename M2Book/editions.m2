-- The editions of the book: the generated baseline, and the curated book with
-- edited pages in place of their generated counterparts. Only edited pages and
-- assets are kept, in curated/<package> beside this file; each curated build
-- starts from the current renderer and overlays them in a separate tree.
curatedSources = toAbsolutePath(currentFileDirectory | "curated/")
shellQuote = s -> "'" | replace("'", "'\\\\''", s) | "'"

-- The curated edition of a package's book, written below dir; the package
-- directory.
writeCuratedBook = (pkg, dir, opts) -> (
    destination := toAbsolutePath(dir | "/" | pkg#"pkgname");
    if substring(0, #curatedSources, destination | "/") === curatedSources then
        error "M2Book: build outside curated/ to preserve the edited sources";
    bookDir := writeBookEdition(pkg, dir, opts, "Curated");
    overrides := curatedSources | pkg#"pkgname";
    if isDirectory overrides then (
        if run("cp -R -- " | shellQuote(overrides | "/.") | " " | shellQuote bookDir) != 0 then
            error("M2Book: could not apply curated files from ", overrides));
    bookDir
)

-- edition => the function writing a package's book in it below a directory
bookEditions = hashTable {
    "Curated" => writeCuratedBook,
    "Generated" => (pkg, dir, opts) -> writeBookEdition(pkg, dir, opts, "Generated")
}
