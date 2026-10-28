needsPackage "Macaulay2Doc"
needsPackage "JSON"
needsPackage "Text"

-- ---------------------------------------------------------------------------
-- Schema field vocabulary. The record HashTables are keyed by capitalised
-- `*Fun` symbols rather than string literals, so the field set is a single,
-- renameable, cross-file-referenceable vocabulary -- an editor can rename
-- `KindFun` everywhere; it cannot rename the string "kind". The `Fun` suffix
-- keeps them clear of the M2 builtins their capitalised names would otherwise
-- be (Options, Version, Authors, TypicalValue, Name, Email, ...).
--
-- The on-the-wire JSON key is DERIVED from the symbol: drop `Fun`, convert
-- CamelCase to snake_case. That reproduces every field name except the handful
-- the schema happens to spell in camelCase, listed explicitly in
-- `irregularFields` (plus the function-level `typical_value`, whose symbol
-- would otherwise derive to `typical_value_field`). String keys -- the
-- `properties` flag map, the operator `attributes` form names -- are data, not
-- schema fields, and pass through unchanged.
-- The field vocabulary, protected so they are stable key tokens (and so the
-- package-close check catches a mistyped field name as an unset symbol). The
-- on-the-wire strings are NOT listed here -- they are derived below.
schemaFields = {
    KindFun, NameFun, NormalizedNameFun, SlugFun, ExtraKeysFun, AliasesFun,
    PackageFun, ClassFun, PropertiesFun, TagsFun, ProtectedFun, MutableFun, BriefFun,
    DescriptionFun, ExamplesFun, SeeAlsoFun, SourceFun, SourceLocationFun,
    DocSourceFun, LastUpdateFun, VAddedFun, VLastChangeFun, DocEntriesFun,
    DomainFun, DomainDescriptionFun, EvaluatedOptionsFun, TypicalValueFun,
    ExactFun, CodomainDescriptionFun, OptionsFun, ValueStringFun, OptionKeyForFun,
    SizeFun, TypicalValueFieldFun, MethodsFun, FormFun, ArityFun, SideFun,
    FlexibleFun, TokenFun, FormsFun, AttributesFun, AssignmentFun, OperatorFun, KeyFun,
    DefaultFun, ValueTypeFun, PossibleValuesFun, RawFun, FilenameFun, StartRowFun,
    StartColFun, StopRowFun, StopColFun, LinenumFun, PathFun, ParentFun,
    AncestorsFun, SubtypesFun, InstancesFun, ConstructorsFun, CommonOperationsFun,
    TitleFun, VersionFun, AuthorsFun, ExportsFun, FunctionsFun, OperatorsFun,
    TypesFun, ObjectsFun, ConfigVarsFun, HistoryVarsFun, EmailFun, HomepageFun
}
scan(schemaFields, protect)

-- The few fields the schema spells in camelCase (every other field's JSON key
-- derives by CamelCase->snake_case below); `typical_value` is the function-level
-- field whose symbol would otherwise derive to `typical_value_field`.
irregularFields = hashTable {
    DomainDescriptionFun => "domainDescription",
    CodomainDescriptionFun => "codomainDescription",
    TypicalValueFun => "typicalValue",
    EvaluatedOptionsFun => "evaluatedOptions",
    ValueTypeFun => "valueType",
    PossibleValuesFun => "possibleValues",
    TypicalValueFieldFun => "typical_value"
}

camelToSnake = s -> replace("^_", "", toLower replace("([A-Z])", "_\\1", s))

-- A record key's JSON field name: symbols derive (irregular overrides first,
-- else drop `Fun` + CamelCase->snake); string keys are data, kept verbatim.
jsonFieldKey = k -> (
    if not instance(k, Symbol) then
        k
        else if irregularFields#?k then
        irregularFields#k
        else camelToSnake replace("Fun$", "", toString k)
)

-- Recursively rewrite a record's symbol keys to their JSON field names; string
-- keys (data) and all values pass through, recursing into nested tables/lists.
jsonReady = x -> (
    if instance(x, HashTable) then
        applyPairs(x, (k, v) -> (jsonFieldKey k, jsonReady v))
        else if instance(x, BasicList) and not instance(x, String) then
        apply(x, jsonReady)
        else x
)

-- ---------------------------------------------------------------------------
-- Name normalisation. Used as the basis for filenames, primary keys, and
-- the `normalized_name` ReferenceKey. Special characters are escaped in
-- three passes (longest first) to avoid collisions between, e.g., `=` and
-- `==` -- the longer pattern is applied first so the shorter one never
-- sees its own output.
-- ---------------------------------------------------------------------------

escapeRaw := hashTable {
    "." => "dot",
    "+" => "add",
    "*" => "mul",
    "?" => "mark",
    "!" => "bang",
    "$" => "usd",
    "%" => "perc",
    "&" => "amp",
    "@" => "at",
    "#" => "hash",
    "^" => "pow",
    "`" => "0qt",
    "'" => "1qt",
    "\"" => "2qt",
    "~" => "inv",
    "|" => "pipe",
    "<" => "lt",
    ">" => "gt",
    "=" => "eq",
    ":" => "col",
    ";" => "scol",
    "," => "cma",
    "/" => "slash",
    "\\" => "bs",
    "(" => "lpar",
    ")" => "rpar",
    "[" => "lbrk",
    "]" => "rbrk",
    "{" => "lbrc",
    "}" => "rbrc",
    " " => "spc",
    "\u22a0" => "box",
    "\u29e2" => "xd",
    "_" => "us"
}

escapeNames := applyKeys(escapeRaw, regexQuote)

escapeNamesSingle := applyValues(escapeNames, x -> "_" | x | "_")

-- A literal underscore can appear in operator names (e.g. `|_=`; `_` is the
-- subscript operator). It must be escaped FIRST and separately from the rest:
-- once the other escapes run, every special char becomes a `_word_` token, and
-- re-applying the underscore rule over those delimiters is what produced the
-- old cascade (`+` -> `_add_` -> `___add___`). Doing `_` first keeps every
-- escape a single `_word_`.
escapeUnderscore := escapeNamesSingle#"_"
escapeNamesRest := new HashTable from select(pairs escapeNamesSingle, p -> p#0 =!= "_")

unEscape := applyKeys(
    new HashTable from apply(pairs escapeRaw, p -> ("_" | p#1 | "_", p#0)),
    regexQuote
)

replaceAll = (s, h) -> (
    result := s;
    for p in pairs h do (
        result = replace(p#0, p#1, result);
    );
    result
)

replaceEach = (s, l) -> (
    result := s;
    for p in l do (
        result = replace(p, result);
    );
    result
)

normalizeName = x -> replaceAll(replace("_", escapeUnderscore, x), escapeNamesRest)

denormalizeName = x -> replaceAll(x, unEscape)

filenameFor = name -> normalizeName name

-- ---------------------------------------------------------------------------
-- Extraction filters.  Non-ASCII names are Unicode aliases of ASCII
-- symbols and should be skipped, except for the two operator symbols
-- (U+22A0 and U+29E2) that have no ASCII equivalents.
-- Purely symbolic operator names (no letters/digits) are punctuation
-- best documented under their word forms.
-- ---------------------------------------------------------------------------

isPunctuationName = name -> not match("[a-zA-Z0-9]", name)
hasNonAscii = name -> match("[^\\x00-\\x7F]", name)

-- The two non-ASCII operators with NO ASCII spelling (U+22A0, U+29E2); every
-- other non-ASCII operator is an alias of an ASCII one and is dropped. Match the
-- literal codepoint (M2 interprets \u in a string literal); regexQuote so the
-- multibyte char matches literally -- a bare "\\u22a0" regex does NOT work
-- (Boost regex has no \u codepoint escape).
keepNonAscii = name -> (
    match(regexQuote "⊠", name) or match(regexQuote "⧢", name)
)

shouldExtractName = name -> (
    if hasNonAscii(name) then
        keepNonAscii(name)
        else
        not isPunctuationName(name)
)

-- ---------------------------------------------------------------------------
-- Generic runtime helpers
-- ---------------------------------------------------------------------------

stringList = values -> apply(values, value -> toString value)
safeString = x -> if x =!= null then try toString x
safeClass = x -> try toString class x
emptyHash = hashTable {}
emptyList = {}
valueFailed = new MutableHashTable

-- Enum member for an introspection whose answer genuinely could not be
-- determined (the underlying test errored). A dedicated protected symbol rather
-- than null: null is itself a documented object in the corpus, so reusing it as
-- "unknown" conflates two distinct things.
protect symbol Indeterminate

isFunctionValue = value -> try instance(value, Function) else false
isFunctorValue = value -> try instance(value, ScriptedFunctor) else false
isCommandValue = value -> try instance(value, Command) else false
isManipulatorValue = value -> try instance(value, Manipulator) else false
isCallableValue = value -> (
    isFunctionValue(value) or isFunctorValue(value) or isCommandValue(value) or isManipulatorValue(value)
)

-- Method functions are the only callables that support method installation
-- (overloading by domain via `f T := ...`). M2 has exactly four such runtime
-- classes and -- crucially -- they share no common supertype below `Function`
-- (`MethodFunction`'s parent is `CompiledFunctionClosure`; the other three's is
-- `FunctionClosure`), so detection must be explicit class-name membership.
-- Every other callable (plain `FunctionClosure`/`CompiledFunction`,
-- `ScriptedFunctor`, `Command`, `Manipulator`) is a single, non-overloadable
-- `function`. Verified against the full Core symbol census in v1.26.05.
methodFunctionClassNames = set {
    "MethodFunction", "MethodFunctionSingle",
    "MethodFunctionBinary", "MethodFunctionWithOptions"
}
isMethodFunctionClass = className -> methodFunctionClassNames#?className

referenceKey = value -> if value =!= null then normalizeName(toString(value))

shortNameForRecordName = name -> (
    parts := separate("[$]", name);
    if #parts > 1 then
        last parts
        else
        name
)

normalizedNameForRecordName = name -> normalizeName(shortNameForRecordName(name))

-- Package is read straight off the symbol, so this works for any package, not
-- just Core. The `Core$name` dictionary entries are package-qualified aliases
-- (surfaced in `aliases`); the canonical record name is always the bare symbol.
packageForSymbol = sym -> if sym =!= null then (try toString package sym)

-- ---------------------------------------------------------------------------
-- Source location + text. `locate x` returns a FilePosition -- a BasicList
-- {filename, startRow, startCol, stopRow, stopCol, ...} whose slot-0 filename
-- is an ABSOLUTE, readable path -- or null when M2 records no position
-- (compiled built-ins, where the source is C++). It accepts a symbol, a
-- function value, OR a method signature Sequence like `(kernel, Matrix)`.
-- We read the literal source lines from the file span rather than scraping
-- `code`'s rendering, which bakes in volatile build paths and stacks
-- strategy-hook blocks. `code`/`locate` error on ScriptedFunctors, so guard.
sourceFilePath = filename -> (
    if member(filename, {"currentString", "stdio"}) then null
    else toAbsolutePath filename
)

sourceLocationFor = x -> (
    lp := try locate x;
    if not instance(lp, FilePosition) or #lp < 5 then return null;
    if not all({lp#1, lp#2, lp#3, lp#4}, coordinate -> instance(coordinate, ZZ)) then return null;
    if lp#1 < 1 or lp#3 < lp#1 or lp#2 < 0 or lp#4 < 0 then return null;
    if lp#1 == lp#3 and lp#4 < lp#2 then return null;
    filename := if instance(lp#0, String) then sourceFilePath lp#0;
    if filename === null then return null;
    if instance(lp#0, String) then
        try hashTable {
        FilenameFun => filename,
        StartRowFun => lp#1, StartColFun => lp#2,
        StopRowFun => lp#3, StopColFun => lp#4
    }
)

-- Core builds some functions as closures around another function, so `locate`
-- reports Core's wrapper instead of the definition. Like Core's `codeHelper`,
-- recognise a wrapper by its function body. Each entry gives the function it
-- wraps, or null when it combines several and no single definition exists.
capturedFunction = closure -> (
    captured := select(toList first frames closure, v -> instance(v, Function));
    if #captured == 1 then first captured
)
wrappedFunctions = hashTable {
    functionBody({} >> identity) => capturedFunction,
    functionBody(true >> identity) => capturedFunction,
    functionBody memoize identity => capturedFunction,
    functionBody (cacheValue null) identity => capturedFunction,
    functionBody (stashValue null) identity => capturedFunction,
    functionBody(identity @@ identity) => closure -> null
}

functionSourceLocation = f -> (
    body := if instance(f, FunctionClosure) then functionBody f;
    if wrappedFunctions#?body then (
        wrapped := wrappedFunctions#body f;
        if wrapped =!= null then functionSourceLocation wrapped)
    else sourceLocationFor f
)

-- `locate` reinterprets other values: an integer indexes the last `methods`
-- listing and a sequence is read as a method key, so only functions and
-- packages have a location of their own.
valueSourceLocation = value -> (
    if instance(value, Function) then functionSourceLocation value
    else if instance(value, Package) then sourceLocationFor value
)

-- Methods installed on a compiled function only declare its typical value;
-- the compiled function never dispatches to them.
methodSourceLocation = signature -> (
    if instance(first signature, CompiledFunction) then return null;
    implementation := try lookup signature;
    if instance(implementation, Function) then functionSourceLocation implementation
    else sourceLocationFor signature
)

-- Cache file contents: the full corpus has many records per source file, and
-- `get` re-reads from disk each call.
fileLinesCache = new MutableHashTable
fileLinesFor = fn -> (
    if not fileLinesCache#?fn then
        fileLinesCache#fn = if fileExists fn then (try lines get fn);
    fileLinesCache#fn
)

sourceTextFor = loc -> (
    if loc === null then
        return null;
    lns := fileLinesFor loc#FilenameFun;
    if lns === null then
        return null;
    sr := loc#StartRowFun;
    er := loc#StopRowFun;
    if not (not (instance(sr, ZZ) and instance(er, ZZ)) or sr < 1 or er > #lns or sr > er) then
        demark("\n", take(lns, {sr - 1, er - 1}))
)

-- A protected symbol cannot be reassigned (M2's `protect`). `mutable sym` is
-- M2's reliable test for assignability -- `isProtected` is not a usable
-- one-argument function -- so protected is its negation. `Indeterminate` when
-- the test errors. Callers always pass a real symbol, so null-guarding the
-- input is not this function's responsibility.
isSymbolProtected = sym -> try not isMutable sym else Indeterminate

-- "Runtime value": the symbol holds data (a config/metadata value set during
-- this M2 run) rather than being a self-named library entity. M2 registers
-- functions, types, and named constants in its ReverseDictionary so their value
-- prints as the symbol's name; a symbol carrying plain data (version's table,
-- `path`, `debugLevel`, ...) prints the data instead. So the value's `toString`
-- differing from the symbol's name marks a dynamic runtime value.
hasDynamicValue = (sym, value) -> try (toString value =!= toString sym) else false

-- ---------------------------------------------------------------------------
-- Kind decision
-- ---------------------------------------------------------------------------

recordKind = (sym, value, className, name) -> (
    if operatorAttributes#?sym then "operator"
        else if className === "Package" and not match("[$]", name) then "package"
        else if try instance(value, Type) else false then "type"
        else if isMethodFunctionClass className then "methodFunction"
        else if isCallableValue(value) then "function"
    -- A symbol that evaluates to a symbol stands for itself: a protected enum
    -- member used as an option key and/or value (Verbose, Lex, Strategy, ...).
        else if try instance(value, Symbol) else false then "symbol"
    -- A builtin hashtable or dictionary (typicalValues, operatorAttributes,
    -- PackageDictionary, ...). HashTable/MutableHashTable match by EXACT class --
    -- their other subclasses are Types, Packages, etc., not tables -- whereas
    -- every subclass of CacheTable/OptionTable/DocumentTag/Dictionary counts (so
    -- GlobalDictionary/LocalDictionary are caught). After the callable check so
    -- ScriptedFunctors, which are also HashTables, stay functions.
        else if (
        className === "HashTable" or className === "MutableHashTable"
        or (try instance(value, CacheTable) else false)
        or (try instance(value, OptionTable) else false)
        or (try instance(value, DocumentTag) else false)
        or (try instance(value, Dictionary) else false)
    ) then "table"
        else "object"
)

-- ---------------------------------------------------------------------------
-- Per-class property derivation.
-- ---------------------------------------------------------------------------

propertiesFromClass = className -> (
    props := new MutableHashTable;
    if className === "MutableHashTable" or className === "MutableList" then
        props#"mutable" = "";
    if className === "Command" or className === "Manipulator" then
        props#"runtime binding" = "";
    if className === "PseudocodeClosure" then
        props#"semantics left to the user" = "";
    new HashTable from props
)

-- ---------------------------------------------------------------------------
-- Tag derivation. Conservative: only the tags that the doc and runtime data
-- can establish mechanically.
-- ---------------------------------------------------------------------------

tagsForRecord = (db, entriesByName, name) -> (
    docName := if db#?name then name else shortNameForRecordName(name);
    hasDoc := db#?docName;
    if hasDoc then
        {}
        else
        {"undocumented"}
)

-- ---------------------------------------------------------------------------
-- Documentation-database helpers.
-- ---------------------------------------------------------------------------

recordNameFromDocKey = key -> (
    parts := separate("\\(", key);
    name := first parts;
    packageParts := separate("::", name);
    if #packageParts > 1 then
        name = last packageParts;
    name
)

docKeysFromDb = db -> sort unique apply(keys db, toString)

buildDocEntriesByName = db -> (
    docKeys := docKeysFromDb db;
    result := new MutableHashTable;
    scan(docKeys, key -> (
        baseName := recordNameFromDocKey key;
        if db#?key then
            result#baseName = append(result#baseName ?? {}, hashTable {KeyFun => key, RawFun => db#key});
    ));
    result
)

docEntriesForName = (entriesByName, name) -> entriesByName#(shortNameForRecordName(name)) ?? {}

docKeysForName = (entriesByName, name) -> apply(docEntriesForName(entriesByName, name), entry -> entry#KeyFun)

-- Rendering M2 help is one of the most expensive per-record operations. A
-- callable previously rendered the same parent help in extractCommon,
-- funcExtras, and methodRecords. Cache it by package-qualified record identity;
-- multi-package extraction processes each package immediately after loading it,
-- so this also preserves the package-specific resolution of a bare name.
helpCache = new MutableHashTable

cachedHelp = (key, target) -> (
    if helpCache#?key then
        helpCache#key
    else (
        h := try help target;
        helpCache#key = h;
        h
    )
)

helpForRecord = (sym, name) -> (
    pkg := if sym =!= null then packageForSymbol sym;
    key := if pkg =!= null then pkg | "$" | name else name;
    cachedHelp(key, if sym =!= null then sym else name)
)

helpForInstallation = (sym, signature) -> (
    pkg := if sym =!= null then packageForSymbol sym;
    key := (if pkg =!= null then pkg | "$" else "") | toString signature;
    cachedHelp(key, signature)
)

extraKeysForRecord = (entriesByName, name) -> (
    normalized := normalizedNameForRecordName(name);
    sort unique select(join({name}, docKeysForName(entriesByName, name)), key -> key =!= normalized)
)

-- ---------------------------------------------------------------------------
-- Documentation parsing. `help name` returns a DIV hypertext node whose
-- top-level children are HEADER1 (title + ` -- brief`), the Usage/Inputs/
-- Outputs synopsis, an optional `Description` section, See-also and Ways-to-use.
-- `net` of a node renders it to readable text (with `***`/`===` underlines on
-- headers, hence the firstLine trimming below). `toString` of the node would
-- instead dump the raw tag tree, which is unreadable.
-- ---------------------------------------------------------------------------

firstLine = s -> first separate("\n", s)

-- Trim only the boundary lines. The former single alternation
-- `^[[:space:]]+|[[:space:]]+$` can exceed Boost.Regex's complexity guard on
-- very large rendered examples (VectorGraphics exposes one); two simple
-- line-anchored matches keep the work linear in the boundary lines.
stripWs = s -> (
    ls := separate("\n", s);
    while #ls > 0 and match("^[ \t\r]*$", first ls) do ls = drop(ls, 1);
    while #ls > 0 and match("^[ \t\r]*$", last ls) do ls = drop(ls, -1);
    if #ls == 0 then
        ""
    else (
        trimmed := apply(#ls, i -> (
            line := ls#i;
            if i == 0 then line = replace("^[ \t\r]+", "", line);
            if i == #ls - 1 then line = replace("[ \t\r]+$", "", line);
            line
        ));
        demark("\n", trimmed)
    )
)

-- Tidy prose punctuation: drop a space between a word and a following , ; :
-- (but leave `...` alone), ensure a space after . , ; : when a letter follows,
-- and capitalise the first character.
fixPunctuation = s -> (
    if #s == 0 then
        return s;
    s = replace("([A-Za-z]) +([,;:])", "\\1\\2", s);
    -- no space before , ; :
    s = replace("([,;:])([A-Za-z])", "\\1 \\2", s);
    -- space after , ; : before a letter
    -- Space after a period only before a capital -- a sentence boundary. This
    -- leaves URLs (en.wikipedia.org), file refs (Core.m2) and abbreviations
    -- (e.g.) intact.
    s = replace("([.])([A-Z])", "\\1 \\2", s);
    capitalize s
)

capitalize = s -> if #s == 0 then s else toUpper substring(s, 0, 1) | substring(s, 1)

-- Headline brief: the text after ` -- ` on the HEADER1 title line, capitalised.
briefFromHelp = h -> (
    if h === null then
        return null;
    header := null;
    scan(toList h, c -> if instance(c, HEADER1) then header = c);
    if header === null then
        return null;
    parts := separate(" -- ", firstLine toString net header);
    if #parts <= 1 then
        return null;
    b := stripWs demark(" -- ", drop(parts, 1));
    if #b != 0 then
        capitalize b
)

-- Render a doc hypertext subtree to text. Internal links (TO/TO2/TOH) become
-- the schema's `$<normalized_target>` inline form (the link target is the doc
-- key after `Package ::`); code (TT/CODE) becomes backticks; paragraphs are
-- blank-line separated. Nested sections (HEADER2-led DIVs such as Synopsis) and
-- example TABLEs are skipped, so only the prose survives.
linkTarget = tag -> stripWs last separate("::", toString tag)
isSubSection = node -> instance(node, DIV) and #node > 0 and instance(node#0, HEADER2)

docToText = node -> (
    if instance(node, String) then
        node
        else if instance(node, Option) then
        ""
        else if instance(node, COMMENT) then
        ""
        else if instance(node, TABLE) then
        ""
        else if isSubSection node then
        ""
        else if instance(node, TO) or instance(node, TOH) then (
        if #node > 0 then
            "$<" | normalizeName linkTarget node#0 | ">"
            else
            ""
    )
        else if instance(node, TO2) then (
        if #node > 0 then
            "$<" | normalizeName linkTarget node#0 | ">"
            else
            ""
    )
        else if instance(node, HREF) then (
        -- External link: HREF{url, text}. Render as a Markdown link so the URL
        -- and link text don't run together.
        url := if #node > 0 then toString node#0 else "";
        text := if #node > 1 then concatenate apply(drop(toList node, 1), docToText) else url;
        "[" | text | "](" | url | ")"
    )
        else if instance(node, TT) or instance(node, CODE) then (
        "`" | concatenate apply(toList node, docToText) | "`"
    )
        else if instance(node, PARA) then (
        stripWs concatenate apply(toList node, docToText) | "\n\n"
    )
        else if instance(node, Hypertext) then
        concatenate apply(toList node, docToText)
        else
        toString node
)

collectNodes = (node, pred) -> (
    if not instance(node, Hypertext) then
        {}
        else
        join(
        if pred node then
            {node}
            else
            {},
        flatten apply(toList node, c -> collectNodes(c, pred))
    )
)

-- Section DIV whose HEADER2 title matches `title`, or null.
sectionDiv = (h, title) -> (
    found := null;
    scan(toList h, c -> (
        if instance(c, DIV) and #c > 0 and instance(c#0, HEADER2)
        and firstLine(toString net c#0) == title then
            found = c
    ));
    found
)

-- Inner prose of a HEADER2-led section DIV (drops the header itself).
sectionBody = div -> stripWs concatenate apply(drop(toList div, 1), docToText)

-- Sections NOT part of the description: the HEADER1 brief, the synopsis UL
-- (Usage/Inputs/Outputs -> domain/codomain), the See also / Menu cross-refs,
-- and the navigational Ways-to-use / For-the-programmer / Subnodes listings.
nonDescriptionSection = (node, title) -> (
    instance(node, HEADER1) or instance(node, UL)
    or title == "See also" or title == "Menu" or match("^Subnodes", title)
    or match("^Ways to use", title) or match("^For the programmer", title)
    -- auto-generated navigation menus M2 attaches to symbol/type pages
    or match("^Functions with optional argument named", title)
    or match("^Methods that use", title) or match("^Functions and methods", title)
    or match("^Types of ", title)
)

-- Description = the `Description` section plus every other leftover content
-- section (e.g. Caveat), each kept with its `### header`; internal links marked,
-- punctuation tidied. "" when there is no prose.
descriptionFromHelp = h -> (
    if h === null then
        return "";
    blocks := for c in toList h list (
        title := if instance(c, HEADER1) then "" else firstLine toString net c;
        if nonDescriptionSection(c, title) then
            ""
            else (
            body := stripWs(if isSubSection c then sectionBody c else docToText c);
            if #body == 0 then
                ""
                -- the main Description and any untitled block are plain prose; only a
                -- genuinely titled leftover section gets a `### header`.
                else if title == "Description" or #stripWs title == 0 then
                body
                else
                "### " | title | "\n\n" | body
        )
    );
    desc := stripWs demark("\n\n", select(blocks, b -> #b != 0));
    -- Strip M2's source-location footer if it leaks (undocumented symbols).
    desc = stripWs replace("[[:space:]]*The source of this document is in[^\n]*", "", desc);
    -- Drop empty ATX headings -- a stray "###" with no title text is doc-scrape
    -- noise (e.g. exp(Number)); remove such lines and collapse the gap they leave.
    desc = demark("\n", select(separate("\n", desc), l -> not match("^[[:space:]]*#{1,6}[[:space:]]*$", l)));
    desc = stripWs replace("\n{3,}", "\n\n", desc);
    if #desc == 0 then
        ""
        else
        fixPunctuation desc
)

-- See-also targets: the internal links in the `See also` and `Menu` sections
-- (both are pure cross-reference lists), as normalized names.
seeAlsoFromHelp = h -> (
    if h === null then
        return {};
    secs := select({sectionDiv(h, "See also"), sectionDiv(h, "Menu")}, s -> s =!= null);
    sort unique apply(
        flatten apply(secs, s ->
                collectNodes(s, n -> instance(n, TO) or instance(n, TO2) or instance(n, TOH))
        ),
        n -> normalizeName linkTarget n#0
    )
)

-- Synopsis parsing. The synopsis is the first top-level UL; its `Inputs:` and
-- `Outputs:` items each hold a nested UL whose entries read "name, a <type>...".
-- Inputs -> domainDescription map {name => description}; Outputs ->
-- codomainDescription string.
synopsisUL = h -> (
    ul := null;
    scan(toList h, c -> if instance(c, UL) and ul === null then ul = c);
    ul
)

synopsisItem = (ul, label) -> (
    found := null;
    if ul =!= null then
        scan(toList ul, li -> (
        if #li > 0 and instance(li#0, String) and match("^[[:space:]]*" | label, li#0) then
            found = li
    ));
    found
)

paramEntries = li -> (
    if li === null then
        return {};
    nested := null;
    scan(toList li, c -> if instance(c, UL) then nested = c);
    if nested === null then
        return {};
    apply(toList nested, p -> (
        t := stripWs replace("[[:space:]]+", " ", toString net p);
        parts := separate(",", t);
        {stripWs first parts, stripWs demark(",", drop(parts, 1))}
    ))
)

domainDescriptionFromHelp = h -> (
    if h === null then
        return emptyHash;
    entries := select(paramEntries synopsisItem(synopsisUL h, "Inputs"), e -> #(e#0) != 0);
    new HashTable from apply(entries, e -> e#0 => e#1)
)

codomainDescriptionFromHelp = h -> (
    if h === null then
        return "";
    entries := paramEntries synopsisItem(synopsisUL h, "Outputs");
    if #entries == 0 then
        ""
        else
        stripWs demark("; ", apply(entries, e -> stripWs(e#0 | ", " | e#1)))
)

-- The `Consequences` section (side effects) also lives inside the synopsis UL
-- (with Usage/Inputs/Outputs), which descriptionFromHelp skips wholesale -- so it
-- is extracted here directly. Its items are prose (with TO links -> $<...>), not
-- name/desc pairs; render each item's text, blank-line separated.
-- Every synopsis-UL item that is NOT a structured field (Usage/Inputs/Outputs/
-- Optional inputs, handled elsewhere) is a descriptive section -- Consequences and
-- anything else M2 puts there. Render each as a "### Title\n\n body" block, to be
-- folded into the description. The item wraps a DIV whose first child is the
-- title; sectionBody drops that and renders the rest (with TO links -> $<...>).
synopsisProseSections = h -> (
    ul := synopsisUL h;
    if ul === null then
        return "";
    structured := set {"Usage", "Inputs", "Outputs", "Optional inputs"};
    blocks := {};
    scan(toList ul, item -> (
        title := stripWs replace("\"", "", replace(":.*$", "", firstLine toString net item));
        if #title != 0 and not structured#?title then (
            body := stripWs concatenate apply(select(toList item, c -> instance(c, DIV)), sectionBody);
            if #body == 0 then
                body = stripWs concatenate apply(select(toList item, c -> instance(c, Hypertext)), docToText);
            if #body != 0 then
                blocks = append(blocks, "#### " | title | "\n\n" | fixPunctuation body)
        )
    ));
    demark("\n\n", blocks)
)

-- Examples as [input, output] pairs. The rendered help embeds each example as
-- a CODE node holding an `iN : input` / `oN = output` / `oN : type` block (the
-- boxes you see in `net`). We collect those CODE nodes, identify the example
-- ones by their `iN :` prompt, and split each into input (prompt stripped) and
-- output (kept verbatim; empty for `;`-suppressed setup lines).
collectCodeNodes = node -> (
    if not instance(node, Hypertext) then
        {}
        else
        join(
        if instance(node, CODE) then
            {node}
            else
            {},
        flatten apply(toList node, collectCodeNodes)
    )
)

codeNodeText = node -> concatenate select(toList node, c -> instance(c, String))

parseExampleBlock = txt -> (
    inp := {};
    out := {};
    seenOut := false;
    for l in separate("\n", txt) do (
        if match("^i[0-9]+ +: ", l) then
            inp = append(inp, replace("^i[0-9]+ +: ", "", l))
            else if match("^o[0-9]+ ", l) then (
            seenOut = true;
            out = append(out, l)
        )
            else if #l != 0 then (
            if seenOut then
                out = append(out, l)
                else
                inp = append(inp, l)
        )
    );
    {stripWs demark("\n", inp), stripWs demark("\n", out)}
)

examplesFromHelp = h -> (
    if h === null then
        {}
        else
        apply(
        select(collectCodeNodes h, c -> match("^i[0-9]+ +:", codeNodeText c)),
        c -> parseExampleBlock codeNodeText c
    )
)

-- The raw documentation database stores each entry as the M2 source of a
-- HashTable carrying, among the rendered hypertext, `"filename"` and
-- `"linenum"` -- the .m2 doc-source file (relative to the Macaulay2Doc package
-- source directory) and line where the `document {...}` / `doc ///...///` block
-- begins. Pulling them by regex (rather than `value`-ing the whole entry, which
-- needs every hypertext constructor visible) gives a stable pointer into the
-- literal doc source, which is easier to parse than rendered help.
-- Candidate doc-source directories, one per extracted package. Core's docs live
-- in Macaulay2Doc; every other package keeps its own, and the relative filename
-- a doc entry records is relative to *its* package's source directory. buildReference
-- populates this with every target package's "source directory"; resolveDocSourcePath
-- tries each so a relative filename resolves against whichever dir actually holds it.
-- Defaults to Macaulay2Doc's so Core-only extraction works without any setup.
docSourceDirs = {}

resolveDocSourcePath = filename -> (
    dirs := if #docSourceDirs > 0 then docSourceDirs
        else select({try Macaulay2Doc#"source directory" else null}, d -> d =!= null);
    existing := select(apply(dirs, dir -> dir | filename), fileExists);
    if #existing > 0 then first existing
)

regexCap1 = (re, s) -> (
    hits := try regex(re, s);
    if hits =!= null and #hits > 1 then
        substring(hits#1, s)
)

-- {filename, linenum, path}: the doc-block location, with `path` resolved to an
-- absolute readable file when possible. Null when the name has no doc entry.
docSourceForName = (db, name) -> (
    docName := if db#?name then name else shortNameForRecordName(name);
    if not db#?docName then
        return null;
    raw := db#docName;
    filename := regexCap1(///"filename"[[:space:]]*=>[[:space:]]*"([^"]+)"///, raw);
    if filename === null then
        return null;
    linenumStr := regexCap1(///"linenum"[[:space:]]*=>[[:space:]]*([0-9]+)///, raw);
    hashTable {
        FilenameFun => filename,
        LinenumFun => if linenumStr =!= null then value linenumStr,
        PathFun => resolveDocSourcePath filename
    }
)

-- Headline of an option's own doc page, used as its description. M2 keys these
-- as `<function>(...,<Option>=>...)`, e.g. `kernel(...,SubringLimit=>...)`.
optionDocHeadline = (db, funcName, optName) -> (
    key := funcName | "(...," | optName | "=>...)";
    if db#?key then
        regexCap1(///Headline[[:space:]]*=>[[:space:]]*"([^"]+)"///, db#key)
)

-- ---------------------------------------------------------------------------
-- Symbol/value plumbing
-- ---------------------------------------------------------------------------

symbolForName = (runtimeDict, name) -> (
    if runtimeDict#?name then
        runtimeDict#name
        else if isGlobalSymbol name then
        getGlobalSymbol name
)

valueForSymbol = sym -> try value sym else valueFailed

-- ---------------------------------------------------------------------------
-- Synonyms for `aliases`.
-- ---------------------------------------------------------------------------

aliasesForName = (sym, name) -> (
    syns := try apply(findSynonyms sym, toString) else {};
    pkg := packageForSymbol sym;
    -- Keep the package-qualified form (e.g. Core$gcd): it is M2's shadow-proof
    -- alias for the symbol and must still resolve to this record. Drop only the
    -- bare canonical name, which is the record's own normalized_name.
    qualified := if pkg =!= null then {pkg | "$" | name} else {};
    sort unique select(join(syns, qualified), s -> s =!= name)
)

-- ---------------------------------------------------------------------------
-- Identity. The schema's primary key is `normalized_name` (package-free); there
-- is no separate package-qualified key. Records are namespaced by their
-- `package` field and, in the generated docs, by per-package directories. A
-- bare name is resolved against the user's loaded-package order at LSP time.
-- ---------------------------------------------------------------------------

fillMissingFields = (base, extras) -> (
    result := new MutableHashTable from base;
    scan(keys extras, key -> (
        if not result#?key then
            result#key = extras#key;
    ));
    new HashTable from result
)

-- ---------------------------------------------------------------------------
-- Shared method-level envelope. A method installation (one signature of a
-- function) and an operator form are both "a callable specialised by its
-- inputs": each carries the CommonObjectDoc field shape plus method-specific
-- domain/codomain/options, but is nested under a parent record rather than
-- extracted from a global symbol (so extractCommon, which needs a sym/value
-- and does doc/alias/tag lookups, is the wrong source and the wrong
-- granularity). methodRecord and operatorMethodRecord both build this base
-- then add their own extra fields, mirroring how the top-level extractors
-- extend extractCommon.
-- ---------------------------------------------------------------------------

methodBaseRecord = (name, normalizedName, packageKey, domain, typicalValue) -> hashTable {
    KindFun => "function",
    NameFun => name,
    NormalizedNameFun => normalizedName,
    SlugFun => null,
    ExtraKeysFun => {},
    AliasesFun => {},
    PackageFun => packageKey,
    ClassFun => "",
    PropertiesFun => emptyHash,
    TagsFun => {},
    BriefFun => "",
    DescriptionFun => "",
    ExamplesFun => {},
    SeeAlsoFun => {},
    LastUpdateFun => "",
    VAddedFun => null,
    VLastChangeFun => null,
    DomainFun => domain,
    DomainDescriptionFun => emptyHash,
    EvaluatedOptionsFun => null,
    TypicalValueFun => typicalValue,
    -- typicalValue is a LOWER BOUND by default: the result is an instance of it
    -- (possibly a subtype), which M2 cannot distinguish from an exact type. Set
    -- `exact` true (by hand) only when the return type is precise; the
    -- typechecker must otherwise treat the result as any subtype.
    ExactFun => false,
    CodomainDescriptionFun => "",
    OptionsFun => {},
    -- Per-installation source: filled by methodRecords from `locate`/`code` of
    -- the actual signature Sequence; null for operator forms (no installation).
    SourceFun => null,
    SourceLocationFun => null
}

-- ---------------------------------------------------------------------------
-- v2 CommonObjectDoc base. Returns a HashTable following the shared schema
-- fields. Per-kind extractors call this first then fill kind-specific fields.
-- ---------------------------------------------------------------------------

extractCommon = (name, sym, value, db, entriesByName) -> (
    className := safeClass(value);
    kind := recordKind(sym, value, className, name);
    protection := isSymbolProtected sym;
    -- Resolve the documentation once and derive brief/description from it.
    h := helpForRecord(sym, name);
    -- Method-function values point at the shared dispatch machinery; use their
    -- symbol's declaration instead. Other objects prefer their implementation,
    -- falling back to their symbol's declaration when no body is recorded.
    srcLoc := if kind =!= "methodFunction" then valueSourceLocation value;
    if srcLoc === null then srcLoc = sourceLocationFor sym;
    -- "runtime value" tag for symbols whose value is runtime-set data/config.
    tags := tagsForRecord(db, entriesByName, name);
    if hasDynamicValue(sym, value) then
        tags = append(tags, "runtime value");
    -- Every descriptive synopsis section (Consequences and anything else M2 puts
    -- in the synopsis UL beyond the structured Usage/Inputs/Outputs) is folded
    -- into the description as a "### Title" subsection -- it all describes the object.
    fullDescription := descriptionFromHelp h;
    extras := synopsisProseSections h;
    if #extras != 0 then
        fullDescription = (if #fullDescription != 0 then fullDescription | "\n\n" else "") | extras;
    new HashTable from {
        KindFun => kind,
        NameFun => name,
        NormalizedNameFun => normalizedNameForRecordName(name),
        SlugFun => null, -- not auto-generated (per schema)
        ExtraKeysFun => extraKeysForRecord(entriesByName, name),
        AliasesFun => aliasesForName(sym, name),
        PackageFun => referenceKey(packageForSymbol sym),
        ClassFun => referenceKey(className),
        PropertiesFun => propertiesFromClass(className),
        TagsFun => tags,
        -- wire form: the Indeterminate enum becomes the schema's `boolean?`
        -- null (unknown); true/false pass through unchanged.
        ProtectedFun => (if protection =!= Indeterminate then protection),
        MutableFun => (if protection =!= Indeterminate then not protection),
        BriefFun => briefFromHelp h,
        DescriptionFun => fullDescription,
        ExamplesFun => examplesFromHelp h,
        SeeAlsoFun => seeAlsoFromHelp h,
        SourceFun => sourceTextFor srcLoc,
        SourceLocationFun => srcLoc,
        DocSourceFun => docSourceForName(db, name),
        LastUpdateFun => "",
        VAddedFun => null, -- M2 exposes no per-symbol version info
        VLastChangeFun => null
    }
)

-- A dynamic/runtime value (path, currentDirectory, ...) is machine- and
-- session-specific -- often the user's own filesystem -- so it is NOT a documented
-- fact about the object; omit the value dump for those (keep it for genuine constants).
extractObject = (name, sym, value, db, entriesByName) -> fillMissingFields(
    extractCommon(name, sym, value, db, entriesByName),
    hashTable {ValueStringFun => if not hasDynamicValue(sym, value) then safeString value}
)

-- A protected enum-member symbol (an option key and/or value, e.g. Verbose,
-- Lex). `option_key_for` is filled by a second pass (see reference.m2) with the
-- functions that accept it as an option key; option-VALUE usage is not
-- introspectable at compile time, so it is not captured here.
extractSymbol = (name, sym, value, db, entriesByName) -> fillMissingFields(
    extractCommon(name, sym, value, db, entriesByName),
    hashTable {OptionKeyForFun => {}}
)

-- A builtin hashtable or dictionary (e.g. typicalValues, operatorAttributes,
-- PackageDictionary). `size` is the entry count; the contents are not dumped --
-- some of these hold thousands of entries.
extractTable = (name, sym, value, db, entriesByName) -> fillMissingFields(
    extractCommon(name, sym, value, db, entriesByName),
    hashTable {SizeFun => (try #value)}
)

recordToJSON = record -> toJSON jsonReady record
