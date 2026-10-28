-- A package's documentation as a book in the browser, as viewHelp shows the HTML
-- documentation: written in a layout below the application directory, made an
-- mdBook source, and served by mdbook serve in the background. A server keeps
-- serving its book, rebuilding it when it is written again, until M2 exits.

viewerDirectory := () -> applicationDirectory() | "M2Book/"

-- The port of the first server; each further book is served on the next port.
firstPort := 3000
-- book directory => (process id, port) of the server serving it
bookServers := new MutableHashTable

bookToolsInstaller := toAbsolutePath(currentFileDirectory | "install_book_tools.sh")
bookToolNames := {"mdbook", "mdbook-tsitter", "mdbook-katex"}

bookToolsRoot := () -> (
    configured := getenv "M2BOOK_TOOLS_ROOT";
    if configured =!= null and #configured > 0 then configured
    else applicationDirectory() | "M2Book/tools"
)

bookCommand := command -> (
    cargoHome := getenv "CARGO_HOME";
    if cargoHome === null or #cargoHome == 0 then cargoHome = getenv "HOME" | "/.cargo";
    "PATH=" | shellQuote(getenv "PATH" | ":" | bookToolsRoot() | "/bin:" | cargoHome | "/bin")
        | " " | command
)

missingBookTools := () -> select(bookToolNames, tool ->
    run bookCommand("command -v " | shellQuote tool | " >/dev/null 2>&1") != 0)

installBookTools = () -> (
    missing := missingBookTools();
    if #missing > 0 then (
        << "M2Book needs: " << demark(", ", missing) << endl;
        needsCargo := run bookCommand("command -v cargo >/dev/null 2>&1") != 0;
        if needsCargo then (
            << "Cargo is missing. Setup will install Rust and Cargo using rustup, then the missing book tools." << endl
        ) else << "Setup will install the missing book tools using Cargo." << endl;
        << "It also checks math rendering and prepares the syntax parsers." << endl;
        << (if needsCargo then "Install Rust/Cargo and the missing book tools now? [y/N] "
            else "Install the missing book tools now? [y/N] ") << flush;
        answer := try read() else "";
        if not instance(answer, String) or not match("^[[:space:]]*([Yy]|[Yy][Ee][Ss])[[:space:]]*$", answer) then
            return false;
    );
    status := run bookCommand("M2BOOK_TOOLS_ROOT=" | shellQuote bookToolsRoot()
        | " bash " | shellQuote bookToolsInstaller);
    if status != 0 then error "M2Book: book tools setup failed; see the output above";
    missing = missingBookTools();
    if #missing > 0 then error("M2Book: book tools are still missing: ", demark(", ", missing));
    true
)

ensureBookTools := () -> (
    if #missingBookTools() > 0 and not installBookTools() then
        error "M2Book: opening the book was cancelled; dependencies were not installed"
)

-- The server of a book directory, started when there is none; its address.
bookAddress := bookDir -> (
    if not bookServers#?bookDir then (
        port := firstPort + #bookServers;
        log := viewerDirectory() | baseFilename bookDir | "-" | toString port | ".log";
        processId := value get("!" | bookCommand concatenate("mdbook serve --hostname 127.0.0.1 --port ", toString port,
            " --dest-dir ", shellQuote(viewerDirectory() | "site/" | toString port | "/" | baseFilename bookDir), " ",
            shellQuote bookDir, " > ", shellQuote log, " 2>&1 & echo $!"));
        -- mdbook serve builds the book before it listens, and exits when it fails
        sleep 1;
        if run("kill -0 " | toString processId) != 0 then
            error("M2Book: mdbook serve failed:\n", get log);
        bookServers#bookDir = (processId, port));
    concatenate("http://127.0.0.1:", toString last bookServers#bookDir, "/")
)

addEndFunction(() -> scan(values bookServers, server -> run("kill " | toString first server)))

-- (edition, package name) => the directory of the book written this session
writtenBooks := new MutableHashTable

-- The address of a package's book in an edition: written below the application
-- directory on first use in a session, then served until M2 exits.
editionAddress := (edition, pkgname) -> (
    if not bookEditions#?edition then
        error("viewBook: expected Edition to be one of ", demark(", ", sort keys bookEditions));
    ensureBookTools();
    if not writtenBooks#?(edition, pkgname) then
        writtenBooks#(edition, pkgname) = bookEditions#edition(needsPackage pkgname,
            viewerDirectory() | toLower edition, options generateBookBase);
    bookAddress writtenBooks#(edition, pkgname)
)

-- viewBook is a command, as viewHelp is: without an argument it opens the book
-- of Macaulay2Doc.
viewBookMethod := method(Dispatch => Thing, Options => {Edition => "Curated"})
viewBookMethod Thing := String => opts -> key -> viewBookMethod(
    if key === () then "Macaulay2Doc" else makeDocumentTag key, opts)
viewBookMethod String := String => opts -> key -> viewBookMethod(makeDocumentTag key, opts)
viewBookMethod DocumentTag := String => opts -> tag -> (
    page := bookPageFile tag;
    if page === null then error("viewBook: no page of the book shows ", format tag);
    address := editionAddress(opts.Edition, page#0) | page#1;
    show URL address;
    address
)
viewBook = new Command from viewBookMethod
