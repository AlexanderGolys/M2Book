-- Setting up the book tools, without installing into the user's environment:
-- the installer and the M2 commands run with fake cargo, rustup, curl and
-- mdbook executables on a PATH of their own.
--
-- Usage:
--   M2 --script tests/bookTools.m2

load "./harness.m2"

installerScript = repositoryRoot | "scripts/install_book_tools.sh"

-- A renderer that builds a page showing math and highlighted code.
rendererScript = ///#!/bin/bash
mkdir -p "$2/book"
printf '%s\n' '<span class="katex">math</span><pre class="treesitter">code</pre>' > "$2/book/check.html"
printf '%s\n' "$2" >> "$BUILD_LOG"
///

-- The commands the installer needs from the system, besides the fakes.
systemCommands = {"bash", "sh", "mkdir", "mktemp", "rm", "grep", "cp", "cat",
    "dirname", "date", "sleep"}

-- A scratch directory with a bin directory of system commands, and the
-- environment the installer and M2 run with.
newFixture = () -> (
    root := scratchDirectory "m2book-setup";
    bin := root | "/bin";
    makeDirectory bin;
    scan(systemCommands, command -> symlinkFile(commandPath command, bin | "/" | command));
    new MutableHashTable from {
        "root" => root,
        "bin" => bin,
        "environment" => new MutableHashTable from {
            "PATH" => bin,
            "M2BOOK_TOOLS_ROOT" => root | "/installed tools",
            "CARGO_HOME" => root | "/cargo home",
            "RUSTUP_HOME" => root | "/rustup home",
            "RUSTUP_LOG" => root | "/rustup.log",
            "INSTALL_LOG" => root | "/install.log",
            "BUILD_LOG" => root | "/build.log"}})

withFixture = body -> (
    fixture := newFixture();
    body fixture;
    removeScratch fixture#"root")

setting = (fixture, name) -> fixture#"environment"#name
logLines = (fixture, name) -> lines get setting(fixture, name)

-- An executable file in the fixture's bin directory.
executable = (fixture, name, contents) -> (
    path := fixture#"bin" | "/" | name;
    path << contents << close;
    if run("chmod 755 " | shellQuote path) != 0 then error("tests: could not make ", path, " executable");
    path)

-- A cargo installing every tool it is asked for; mdbook as the renderer.
fakeCargo = fixture -> (
    executable(fixture, "cargo", ///#!/bin/bash
printf '%s\n' "$*" >> "$INSTALL_LOG"
while (( $# )); do
    if [[ "$1" == --root ]]; then root="$2"; shift; fi
    tool="$1"
    shift
done
mkdir -p "$root/bin"
if [[ "$tool" == mdbook ]]; then
    cp "$RENDERER_FIXTURE" "$root/bin/$tool"
else
    printf '#!/bin/bash\nexit 0\n' > "$root/bin/$tool"
fi
chmod +x "$root/bin/$tool"
///);
    symlinkFile(commandPath "chmod", fixture#"bin" | "/chmod");
    renderer := fixture#"root" | "/renderer";
    renderer << rendererScript << close;
    run("chmod 755 " | shellQuote renderer);
    fixture#"environment"#"RENDERER_FIXTURE" = renderer)

fakePreprocessors = fixture -> scan({"mdbook-tsitter", "mdbook-katex"}, tool ->
    executable(fixture, tool, "#!/bin/bash\nexit 0\n"))

-- No cargo, but a curl downloading a rustup installer that provides it.
fakeRustup = fixture -> (
    fakeCargo fixture;
    cargoFixture := fixture#"root" | "/cargo-fixture";
    moveFile(fixture#"bin" | "/cargo", cargoFixture);
    fixture#"environment"#"CARGO_FIXTURE" = cargoFixture;
    installer := fixture#"root" | "/rustup-fixture";
    installer << ///#!/bin/sh
printf '%s\n' "$*" > "$RUSTUP_LOG"
mkdir -p "$CARGO_HOME/bin"
cp "$CARGO_FIXTURE" "$CARGO_HOME/bin/cargo"
chmod +x "$CARGO_HOME/bin/cargo"
/// << close;
    fixture#"environment"#"RUSTUP_FIXTURE" = installer;
    executable(fixture, "curl", ///#!/bin/bash
while (( $# )); do
    if [[ "$1" == --output ]]; then cp "$RUSTUP_FIXTURE" "$2"; exit; fi
    shift
done
exit 1
///))

runSetup = fixture -> runCommand(shellQuote installerScript,
    new HashTable from fixture#"environment", "")

-- A Macaulay2 program run with M2Book loaded from this checkout and an answer
-- to its prompts.
runM2 = (fixture, program, answer) -> (
    source := fixture#"root" | "/setup.m2";
    source << "load " << format(repositoryRoot | "scripts/load_package.m2") << ";\n"
        << program << "\nexit 0\n" << close;
    runCommand(demark(" ", apply({commandPath "timeout", "60", m2Executable, "--script", source},
        shellQuote)), new HashTable from fixture#"environment", answer))

installedTools = commands -> apply(commands, command -> last separate(" ", command))

-----------------------------------------------------------------------------
-- The installer
-----------------------------------------------------------------------------

testCase("cargo installs the missing tools and checks the parsers", () -> withFixture(fixture -> (
    fakeCargo fixture;
    result := runSetup fixture;
    succeeds(result, "setup");
    commands := logLines(fixture, "INSTALL_LOG");
    expect(installedTools commands == {"mdbook", "mdbook-tsitter", "mdbook-katex"},
        "every tool installed", result);
    expect(all(commands, command -> match("install --locked --root", command)),
        "locked installs into the tools root", result);
    expect(fileExists setting(fixture, "BUILD_LOG"), "a test book built", result);
    expect(match("Book tools and parsers are ready", result#"stdout"), "readiness reported", result);
    expect(match("export PATH=", result#"stdout"), "the PATH adjustment printed", result))))

testCase("existing tools are kept without cargo", () -> withFixture(fixture -> (
    renderer := executable(fixture, "mdbook", rendererScript);
    fakePreprocessors fixture;
    result := runSetup fixture;
    succeeds(result, "setup");
    expect(get renderer == rendererScript, "the renderer unchanged", result);
    expect(not fileExists(fixture#"root" | "/installed tools"), "nothing installed", result))))

testCase("cargo installs only the missing preprocessors", () -> withFixture(fixture -> (
    fakeCargo fixture;
    executable(fixture, "mdbook", rendererScript);
    result := runSetup fixture;
    succeeds(result, "setup");
    expect(installedTools logLines(fixture, "INSTALL_LOG") == {"mdbook-tsitter", "mdbook-katex"},
        "only the preprocessors installed", result))))

testCase("missing cargo is installed before the book tools", () -> withFixture(fixture -> (
    fakeRustup fixture;
    result := runSetup fixture;
    succeeds(result, "setup");
    arguments := get setting(fixture, "RUSTUP_LOG");
    scan({"--profile minimal", "--default-toolchain stable", "--no-modify-path"}, argument ->
        expect(match(argument, arguments), "rustup run with " | argument, result));
    expect(#logLines(fixture, "INSTALL_LOG") == 3, "the three tools installed", result);
    expect(fileExists setting(fixture, "BUILD_LOG"), "a test book built", result))))

testCase("a rustup failure stops before the book tools", () -> withFixture(fixture -> (
    fakeRustup fixture;
    setting(fixture, "RUSTUP_FIXTURE") << "#!/bin/sh\nexit 9\n" << close;
    result := runSetup fixture;
    expect(result#"status" == 9, "the rustup exit code", result);
    expect(not fileExists setting(fixture, "INSTALL_LOG"), "no tool installed", result))))

testCase("missing curl says how to continue", () -> withFixture(fixture -> (
    result := runSetup fixture;
    expect(result#"status" == 1, "a failure", result);
    expect(match("Installing Rust and Cargo requires curl", result#"stderr"),
        "curl named as the requirement", result))))

testCase("a failed cargo install does not report success", () -> withFixture(fixture -> (
    executable(fixture, "cargo", "#!/bin/bash\nexit 7\n");
    result := runSetup fixture;
    expect(result#"status" == 7, "the cargo exit code", result);
    expect(not match("parsers are ready", result#"stdout"), "no readiness reported", result))))

testCase("missing rendering is a setup failure", () -> withFixture(fixture -> (
    fakePreprocessors fixture;
    executable(fixture, "mdbook", ///#!/bin/bash
mkdir -p "$2/book"
printf 'plain text' > "$2/book/check.html"
///);
    result := runSetup fixture;
    expect(result#"status" == 1, "a failure", result);
    expect(match("highlighting is missing", result#"stderr"), "the missing highlighting named", result))))

-----------------------------------------------------------------------------
-- The commands of M2Book
-----------------------------------------------------------------------------

testCase("loading keeps the book commands of MarkdownDocs", () -> withFixture(fixture -> (
    result := runM2(fixture, ///assert(mdBook === MarkdownDocs$mdBook);
assert(mdBookPage === MarkdownDocs$mdBookPage);
assert(writeMdBook === MarkdownDocs$writeMdBook);///, "");
    succeeds(result, "loading");
    expect(not match("is shadowed", result#"stdout" | result#"stderr"), "no shadowed command", result))))

testCase("declining or end of input installs nothing", () -> withFixture(fixture -> (
    fakeCargo fixture;
    scan({"n\n", "\n", "", "maybe\n"}, answer -> (
        result := runM2(fixture, "assert(installBookTools() === false);", answer);
        succeeds(result, "declining with " | format answer);
        expect(match("Install the missing book tools now\\?", result#"stdout"), "a prompt", result);
        expect(not fileExists setting(fixture, "INSTALL_LOG"), "no tool installed", result))))))

testCase("an approved install is available in the same session", () -> withFixture(fixture -> (
    fakeCargo fixture;
    fixture#"environment"#"M2BOOK_TOOLS_ROOT" = fixture#"root" | "/installed ' tools";
    result := runM2(fixture,
        "assert(installBookTools() === true); assert(installBookTools() === true);", "yes\n");
    succeeds(result, "installing");
    expect(#select(lines result#"stdout", line -> match("Install the missing book tools now\\?", line)) == 1,
        "a single prompt", result);
    expect(#logLines(fixture, "INSTALL_LOG") == 3, "the three tools installed", result))))

testCase("installing Rust needs explicit approval", () -> withFixture(fixture -> (
    fakeRustup fixture;
    result := runM2(fixture, "assert(installBookTools() === false);", "n\n");
    succeeds(result, "declining");
    expect(match("Install Rust/Cargo and the missing book tools now\\?", result#"stdout"),
        "Rust named in the prompt", result);
    expect(not fileExists setting(fixture, "RUSTUP_LOG"), "rustup not run", result);
    result = runM2(fixture, "assert(installBookTools() === true);", "yes\n");
    succeeds(result, "approving");
    expect(fileExists setting(fixture, "RUSTUP_LOG"), "rustup run", result);
    expect(#logLines(fixture, "INSTALL_LOG") == 3, "the three tools installed", result))))

testCase("viewing a book asks and stops when declined", () -> withFixture(fixture -> (
    fakeCargo fixture;
    result := runM2(fixture,
        ///assert((try viewBook "Graphs" else "cancelled") === "cancelled");///, "n\n");
    succeeds(result, "declining");
    expect(match("Install the missing book tools now\\?", result#"stdout"), "a prompt", result);
    expect(not fileExists setting(fixture, "INSTALL_LOG"), "no tool installed", result))))

testCase("existing tools are checked without a prompt", () -> withFixture(fixture -> (
    fakePreprocessors fixture;
    executable(fixture, "mdbook", rendererScript);
    result := runM2(fixture, "assert(installBookTools() === true);", "");
    succeeds(result, "checking");
    expect(not match("Install the missing book tools now\\?", result#"stdout"), "no prompt", result))))

testCase("viewing a book installs the tools, then serves and opens it", () -> withFixture(fixture -> (
    fakeCargo fixture;
    -- the renderer also serves, recording its arguments
    setting(fixture, "RENDERER_FIXTURE") << ///#!/bin/bash
if [[ "$1" == serve ]]; then
    printf "%s\n" "$@" > "$SERVE_LOG"
    sleep 5
    exit 0
fi
mkdir -p "$2/book"
printf '%s\n' '<span class="katex">math</span><pre class="treesitter">code</pre>' > "$2/book/check.html"
printf '%s\n' "$2" >> "$BUILD_LOG"
/// << close;
    serveLog := fixture#"root" | "/serve.log";
    browserLog := fixture#"root" | "/browser.log";
    fixture#"environment"#"SERVE_LOG" = serveLog;
    fixture#"environment"#"BROWSER_LOG" = browserLog;
    fixture#"environment"#"WWWBROWSER" = executable(fixture, "browser", ///#!/bin/bash
printf '%s\n' "$@" > "$BROWSER_LOG"
///);
    suffix := relativizeFilename(getenv "HOME" | "/", fixture#"root" | "/application") | "/";
    result := runM2(fixture, "applicationDirectorySuffix = " | format suffix | ";\n" |
        ///assert(viewBook "JSON" === "http://127.0.0.1:3000/index.html");///, "y\n");
    succeeds(result, "viewing");
    expect(match("serve", get serveLog), "the book served", result);
    expect(match("http://127.0.0.1:3000/index.html", get browserLog), "the page opened", result);
    expect(fileExists(fixture#"root" | "/application/M2Book/curated/JSON/book.toml"),
        "the curated book written", result))))

testCase("an installation failure is reported to M2", () -> withFixture(fixture -> (
    executable(fixture, "cargo", "#!/bin/bash\nexit 7\n");
    result := runM2(fixture, "assert((try installBookTools() else false) === false);", "y\n");
    succeeds(result, "failing");
    expect(not match("Book tools and parsers are ready", result#"stdout"), "no readiness reported", result))))
