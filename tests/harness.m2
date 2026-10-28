-- Running commands and Macaulay2 scripts in a scratch directory, and checking
-- what they did. A failed check stops the run with the command's output.

needsPackage "JSON"

repositoryRoot = toAbsolutePath(currentFileDirectory | "../")
shellQuote = s -> "'" | replace("'", "'\\\\''", s) | "'"

-- The executables, found before a test narrows the PATH of what it runs.
commandPath = name -> (
    found := lines get("!command -v " | shellQuote name | " || true");
    if #found == 0 then error("tests: ", name, " not found on PATH");
    first found)
m2Executable = (
    configured := getenv "M2_BIN";
    if configured =!= null and #configured > 0 then commandPath configured
    else commandPath "M2")

-- A fresh directory, removed by removeScratch.
scratchDirectory = prefix -> (
    dir := temporaryFileName() | "-" | prefix;
    makeDirectory dir;
    dir)
removeScratch = dir -> if run("rm -rf -- " | shellQuote dir) != 0 then
    error("tests: could not remove ", dir)

-- The exit code and outputs of a shell command run in the repository with the
-- environment variables of a hash table set and the input on its stdin.
runCommand = (command, environment, input) -> (
    dir := scratchDirectory "command";
    dir | "/input" << input << close;
    status := run concatenate("cd ", shellQuote repositoryRoot, " && env ",
        apply(sort pairs environment, (key, value) -> (key, "=", shellQuote value, " ")),
        command, " < ", shellQuote(dir | "/input"),
        " > ", shellQuote(dir | "/stdout"), " 2> ", shellQuote(dir | "/stderr"));
    result := hashTable {
        "status" => status // 256,
        "stdout" => get(dir | "/stdout"),
        "stderr" => get(dir | "/stderr")};
    removeScratch dir;
    result)

-- A Macaulay2 script of the repository, run with its arguments.
runScript = (name, arguments) -> runCommand(
    demark(" ", apply(join({m2Executable, "--script", repositoryRoot | "scripts/" | name},
        apply(arguments, toString)), shellQuote)),
    hashTable {}, "")

-- Stop with the context of a result when a condition does not hold.
expect = (condition, description, result) -> if not condition then error(
    "tests: expected ", description,
    if result =!= null then concatenate(
        "\n-- exit code: ", toString result#"status",
        "\n-- stdout:\n", result#"stdout",
        "\n-- stderr:\n", result#"stderr") else "")
succeeds = (result, description) -> expect(result#"status" == 0, description | " to succeed", result)

-- The records of a JSON Lines file.
readRecords = path -> apply(select(lines get path, line -> #line > 0), fromJSON)
recordsByName = records -> hashTable apply(records, record -> record#"name" => record)

-- Run a named test case, reporting it on stderr.
testCase = (name, body) -> (
    stderr << "-- " << name << " ..." << flush;
    body();
    stderr << " ok" << endl)
