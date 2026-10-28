-- The LSP index: reference pages back to records, the reverse of pages.m2.
--
-- The pages are pure human-facing documentation: they carry no internal
-- bookkeeping (normalized_name, last_update, slug, extra_keys, source
-- provenance) and intentionally omit the blank machine sub-fields. So a page
-- alone cannot reconstruct the full record. Instead we OVERLAY: take the machine
-- record from the extraction corpus (m2-facts.jsonl) as the base, and overlay
-- the human-editable fields parsed from the page on top. Re-extraction never
-- clobbers human edits; human edits never corrupt machine facts.
--
--   full record = machine fields from m2-facts.jsonl
--                 ⊕ human fields parsed from the markdown page
--
-- Two outputs:
--   * full corpus  (every field; the editable reference)
--   * LSP index (compressed: structure + resolution aliases only)

-- The time of the assembly in progress, stamped on the records it overlays.
nowIso = null

-- ---------------------------------------------------------------------------
-- Low-level markdown helpers.
-- ---------------------------------------------------------------------------
-- Hover markdown for the LSP is the rendered reference page itself, with the one
-- book-specific transform reversed: render_markdown escapes a leading `##`/`###`
-- in prose as `\##`/`\###` so its inverse parser does not mistake it for a
-- section split. Strip that backslash so hover shows real headings.
unescapeBookHeadings = s -> demark("\n", apply(separate("\n", s), l ->
    if match("^\\\\#{2,3}([^#]|$)", l) then substring(1, l) else l))
-- The rendered reference pages keep `_undocumented_` markers on empty doc fields
-- so a human editor sees the gap; in LSP hover they are noise, so the index copy
-- of the markdown drops those labeled-bullet marker lines (e.g.
-- `- **See also:** _undocumented_`). Only the marker bullets are removed; real
-- prose and documented sections are untouched.
stripUndocMarkers = s -> demark("\n", select(separate("\n", s),
    l -> not match(///^- \*\*[^*]+:\*\* _undocumented_[[:space:]]*$///, l)))
hoverMarkdownFor = path -> stripUndocMarkers unescapeBookHeadings get path
isFence = ln -> match("^```", ln)
headingLevel = ln -> (m := regex("^(#+) ", ln); if m === null then 0 else #substring(m#1, ln))
headingTitle = ln -> (m := regex("^#+ (.*)$", ln); if m === null then null else stripWs substring(m#1, ln))

trimBlankLines = lns -> (
    a := toList lns;
    start := 0; while start < #a and #stripWs(a#start) == 0 do start = start + 1;
    stop := #a; while stop > start and #stripWs(a#(stop - 1)) == 0 do stop = stop - 1;
    if start >= stop then {} else take(a, {start, stop - 1}))

-- Split lines into (title, bodyLines) at each heading of exactly `level`. Lines
-- before the first such heading are returned under the key `null` (the preamble).
splitAtLevel = (lns, level) -> (
    segs := {}; curTitle := null; cur := {}; inFence := false;
    for ln in lns do (
        if isFence ln then (inFence = not inFence; cur = append(cur, ln))
        else if (not inFence) and headingLevel ln == level then (
            segs = append(segs, (curTitle, cur)); curTitle = headingTitle ln; cur = {})
        else cur = append(cur, ln));
    append(segs, (curTitle, cur)))

-- Restore prose heading lines escaped by the renderer (leading "\#" -> "#").
unescapeProseHeadings = s -> demark("\n", apply(separate("\n", s), l -> if match("^\\\\#", l) then substring(1, l) else l))

-- Reconstruct the canonical reference key from a rendered link href: a resolved
-- path ".../<package>/<kind>/<name>.md" -> "$package$name"; a bare "name.md" ->
-- "name" (target not yet in any extracted package). Input href has no ".md".
keyFromHref = href -> (
    comps := separate("/", href);
    nm := last comps;
    if #comps >= 3 then "$" | comps#(#comps - 3) | "$" | nm else nm)

-- [display](href.md) -> the $<key> prose link marker; the link-text class forbids
-- `[` so a literal bracket in prose (e.g. an interval `[0, h)`) can't swallow a
-- following link. External (non-.md) links are left as-is.
reverseLinkify = s -> (
    s = unescapeProseHeadings s;
    result := ""; rest := s; re := ///\[[^\]\[]*\]\(([^)]+)\.md\)///;
    while (m := regex(re, rest)) =!= null do (
        st := (m#0)#0; ln := (m#0)#1;
        result = result | substring(0, st, rest) | "$<" | keyFromHref substring(m#1, rest) | ">";
        rest = substring(st + ln, rest));
    result | rest)

-- canonical key of a [display](href.md) link (first one), or null.
linkTargetOf = s -> (m := regex(///\]\(([^)]+)\.md\)///, s); if m === null then null else keyFromHref substring(m#1, s))

-- ---------------------------------------------------------------------------
-- Section parsers (human-editable fields only).
-- ---------------------------------------------------------------------------
parseProse = lns -> reverseLinkify demark("\n", trimBlankLines lns)

-- "- **name** — description" bullets -> {name => description}.
parseParams = lns -> new HashTable from select(apply(trimBlankLines lns, ln -> (
    m := regex(///^- \*\*(.+?)\*\* — (.*)$///, ln);
    if m === null then null else (substring(m#1, ln), reverseLinkify substring(m#2, ln)))),
    p -> p =!= null)

-- "- [display](target.md)" bullets -> {target}.
parseRefList = lns -> select(apply(trimBlankLines lns, ln ->
    if match("^- ", ln) then linkTargetOf ln), x -> x =!= null)

-- "- text" bullets -> {text}.
parsePlainList = lns -> select(apply(trimBlankLines lns, ln ->
    if match("^- ", ln) then stripWs substring(2, ln)), x -> x =!= null and #x != 0)

-- "- **Key** — desc (default: `d`, type: `t`, values: `a`, `b`)" -> option record.
optStr = (re, ln) -> (m := regex(re, ln); if m =!= null then substring(m#1, ln))
parseOption = ln -> (
    m := regex(///^- \*\*(.+?)\*\*(.*)$///, ln);
    if m === null then return null;
    rawKey := substring(m#1, ln); rest := substring(m#2, ln);
    -- the key may be a link [Body](...); take the bare symbol name.
    key := (lt := linkTargetOf rawKey; if lt =!= null then last separate("[$]", lt) else rawKey);
    o := new MutableHashTable from {"key" => key};
    d := optStr(///default: `([^`]*)`///, rest);   if d =!= null then o#"default" = d;
    t := optStr(///type: `([^`]*)`///, rest);       if t =!= null then o#"valueType" = t;
    dm := regex(/// — (.*?)( \((?:default|type|values):|$)///, rest);
    if dm =!= null and #substring(dm#1, rest) != 0 then o#"description" = reverseLinkify substring(dm#1, rest);
    new HashTable from o)
parseOptions = lns -> select(apply(select(trimBlankLines lns, ln -> match("^- ", ln)), parseOption), x -> x =!= null)

-- macaulay2/m2-fenced input + optional following plain-fenced output -> [in, out].
parseExamples = lns -> (
    blocks := {}; inF := false; lang := null; cur := {};
    for ln in lns do (
        if isFence ln then (
            if inF then (blocks = append(blocks, (lang, demark("\n", cur))); inF = false; cur = {})
            else (inF = true; lang = stripWs substring(3, ln); cur = {}))
        else if inF then cur = append(cur, ln));
    isCode := l -> l == "macaulay2" or l == "m2";
    exs := {}; i := 0;
    while i < #blocks do (
        inp := (blocks#i)#1;
        if isCode (blocks#i)#0 then (
            if i + 1 < #blocks and not isCode (blocks#(i + 1))#0 then (
                exs = append(exs, {inp, (blocks#(i + 1))#1}); i = i + 2)
            else (exs = append(exs, {inp, ""}); i = i + 1))
        else i = i + 1);
    exs)

-- ---------------------------------------------------------------------------
-- Method-block parsing. Title -> form ("Binary form") or signature name; body ->
-- human method fields (brief blockquote, description prose, Returns fact ->
-- typicalValue/exact, and #### Parameters/Returns/Options/Examples subsections).
-- ---------------------------------------------------------------------------
parseMethodBlock = (title, lns) -> (
    m := new MutableHashTable;
    fm := regex("^(.*) form$", title);
    if fm =!= null then m#"_form" = toLower substring(fm#1, title)
    else m#"_name" = replace("^`|`$", "", title);
    parts := splitAtLevel(lns, 4);
    preamble := (select(parts, p -> p#0 === null))#0#1;
    briefLines := select(preamble, ln -> match("^> ", ln));
    if #briefLines > 0 then m#"brief" = demark("\n", apply(briefLines, ln -> substring(2, ln)));
    scan(select(preamble, ln -> match("^- \\*\\*Returns:\\*\\*", ln)), ln -> (
        tv := linkTargetOf ln;
        if tv =!= null then (
            m#"typicalValue" = tv;
            -- Qualifiers live ONLY in the trailing "(...)" after the link, e.g.
            -- "...md) (exact, inherited)". Match there -- NOT anywhere in the line,
            -- or a type name like "InexactNumber" would falsely trigger "exact".
            quals := (qm := regex(///[.]md\)\s*\(([^)]*)\)///, ln);
                if qm =!= null then substring(qm#1, ln) else "");
            m#"exact" = match("exact", quals);
            if match("common typical value", quals) then m#"returnInherited" = true)));
    descLines := select(preamble, ln ->
        not match("^> ", ln) and not match("^- \\*\\*", ln));
    descParts := (d := parseProse descLines; if #d != 0 and d =!= undocMarker then {d} else {});
    scan(select(parts, p -> p#0 =!= null), p -> (
        if p#0 === "Source" then return;
        sub := convertHumanSection(p#0, p#1);
        if sub =!= null then m#(sub#0) = sub#1
        -- An unrecognised #### sub-heading (e.g. a promoted Caveat) is part of the
        -- description prose, not a method field; fold it back in.
        else descParts = append(descParts, "#### " | p#0 | "\n\n" | parseProse p#1)));
    if #descParts > 0 then m#"description" = demark("\n\n", descParts);
    new HashTable from m)

parseMethods = lns -> apply(select(splitAtLevel(lns, 3), p -> p#0 =!= null),
    p -> parseMethodBlock(p#0, p#1))

-- A human section (## or ####) -> (jsonKey, value), or null if not a known
-- human-editable section (machine sections like Operator/Ancestors are ignored;
-- they come from the corpus).
convertHumanSection = (title, lns) -> (
    if not sectionKeys#?title then return null;
    if stripWs demark("\n", trimBlankLines lns) === undocMarker then return null;
    key := sectionKeys#title;
    val := if key === "description" or key === "codomainDescription" then parseProse lns
        else if key === "domainDescription" then parseParams lns
        else if key === "options" then parseOptions lns
        else if key === "methods" then parseMethods lns
        else if key === "examples" then parseExamples lns
        else if key === "see_also" then parseRefList lns
        else if key === "tags" then parsePlainList lns
        else null;
    if val === null then null else (key, val))

-- ## section title -> human field key. Machine sections are absent here.
-- Detailed method/signature blocks are parsed from their detail section; the
-- short index above is machine-generated (links only) and is ignored here.
sectionKeys = hashTable {
    "Description" => "description", "Parameters" => "domainDescription",
    "Returns" => "codomainDescription",
    "Options" => "options", "Method details" => "methods",
    "Signature details" => "methods", "Examples" => "examples",
    "See also" => "see_also", "Tags" => "tags"}

-- ---------------------------------------------------------------------------
-- Page -> parsed human fields. Path gives normalized_name/package/kind; the H1
-- gives the display name; the lede paragraph gives `brief`; the "Result type"
-- identity fact gives typical_value.
-- ---------------------------------------------------------------------------
parsePage = (path, normalized) -> (
    lns := lines get path;
    h1 := position(lns, ln -> match("^# ", ln));
    name := if h1 =!= null then stripWs substring(2, lns#h1);
    body := if h1 =!= null then drop(lns, h1 + 1) else lns;
    parts := splitAtLevel(body, 2);
    human := new MutableHashTable;
    if name =!= null then human#"name" = name;
    -- Preamble: lede (brief) up to the first identity-fact bullet, then facts.
    preamble := trimBlankLines (select(parts, p -> p#0 === null))#0#1;
    ledeLines := {}; i := 0;
    while i < #preamble and not match("^- \\*\\*", preamble#i) do (ledeLines = append(ledeLines, preamble#i); i = i + 1);
    brief := reverseLinkify demark("\n", trimBlankLines ledeLines);
    if #brief != 0 and brief =!= undocMarker then human#"brief" = brief;
    scan(select(preamble, ln -> match("^- \\*\\*Result type:\\*\\*", ln)), ln -> (
        tv := linkTargetOf ln; if tv =!= null then human#"typical_value" = tv));
    scan(select(parts, p -> p#0 =!= null), p -> (
        kv := convertHumanSection(p#0, p#1);
        if kv =!= null then human#(kv#0) = kv#1));
    new HashTable from human)

-- ---------------------------------------------------------------------------
-- Overlay. Human fields win over the machine base; structured sub-records
-- (methods, options) overlay per element so the base's blank sub-fields survive.
-- ---------------------------------------------------------------------------
topHumanKeys = set {
    "name", "brief", "description", "domainDescription", "codomainDescription",
    "typical_value", "options", "methods", "examples", "see_also", "tags"}
methodHumanKeys = set {
    "brief", "description", "domainDescription", "codomainDescription",
    "typicalValue", "exact", "returnInherited", "options", "examples", "see_also"}

optionKey = o -> if instance(o, HashTable) and o#?"key" then toString o#"key"
-- Canonical method-match key, invariant under de/normalization, so a readable
-- rendered title (e.g. "+(Ideal,Ideal)") matches the facts name ("_add_(Ideal,
-- Ideal)") -- both collapse to the same key.
canonKey = s -> normalizeName denormalizeName s
methodKey = m -> (
    if instance(m, HashTable) and m#?"form" and not isBlankVal m#"form" then "form:" | toString m#"form"
    else if instance(m, HashTable) and m#?"name" and not isBlankVal m#"name" then canonKey toString m#"name")
parsedMethodKey = m -> (
    if m#?"_form" then "form:" | m#"_form"
    else if m#?"_name" then canonKey m#"_name")

-- Overlay parsed sub-record's allowed human fields onto a base sub-record.
overlaySub = (base, parsed, allowed) -> (
    r := new MutableHashTable from base;
    scan(keys parsed, k -> (
        if allowed#?k and not isBlankVal parsed#k then r#k = parsed#k));
    new HashTable from r)

overlayList = (baseList, parsedList, keyOf, parsedKeyOf, allowed) -> (
    byKey := new MutableHashTable;
    scan(parsedList, p -> (k := parsedKeyOf p; if k =!= null then byKey#k = p));
    used := new MutableHashTable;
    merged := apply(baseList, b -> (
        k := keyOf b;
        if k =!= null and byKey#?k then (used#k = true; overlaySub(b, byKey#k, allowed)) else b));
    extra := select(parsedList, p -> (k := parsedKeyOf p; k === null or not used#?k));
    join(merged, apply(extra, p -> overlaySub(new HashTable from {}, p, allowed))))

overlayRecord = (base, human) -> (
    r := new MutableHashTable from base;
    scan(keys human, k -> (
        if not topHumanKeys#?k then return;
        v := human#k;
        if isBlankVal v then return;
        if k === "options" and r#?"options" and instance(r#"options", BasicList) then
            r#"options" = overlayList(toList r#"options", v, optionKey, optionKey, set {"description", "default", "valueType", "possibleValues"})
        else if k === "methods" and r#?"methods" and instance(r#"methods", BasicList) then
            r#"methods" = overlayList(toList r#"methods", v, methodKey, parsedMethodKey, methodHumanKeys)
        else r#k = v));
    r#"last_update" = nowIso;
    remove(r, "doc_entries");
    new HashTable from r)

-- ---------------------------------------------------------------------------
-- Typechecker projection: structural fields + resolution aliases only.
-- ---------------------------------------------------------------------------
topKeep = set {
    "kind", "name", "normalized_name", "package", "class", "aliases", "extra_keys",
    "protected", "mutable", "source_location", "source",
    "typical_value", "methods", "options", "option_passing", "operator",
    "parent", "ancestors", "subtypes", "instances"}
-- Operator installations carry domain/typicalValue (not the old form/arity/side/
-- flexible, which now live in the top-level `operator` field).
methodKeep = set {"domain", "typicalValue", "exact", "returnInherited", "options", "option_passing",
    "source_location", "source"}
-- Options drop their human `description`; only the typecheck-relevant shape stays.
optionKeep = set {"key", "default", "defaultType", "valueType", "possibleValues"}
projectOption = o -> if instance(o, HashTable) then new HashTable from select(pairs o, p -> optionKeep#?(p#0)) else o
projectOptions = os -> if instance(os, BasicList) then apply(toList os, projectOption) else os
projectMethod = m -> if instance(m, HashTable) then (
    mm := new MutableHashTable from select(pairs m, p -> methodKeep#?(p#0));
    if mm#?"options" then mm#"options" = projectOptions mm#"options";
    new HashTable from mm) else m
compressRecord = rec -> (
    h := new MutableHashTable from select(pairs rec, p -> topKeep#?(p#0));
    if h#?"methods" and instance(h#"methods", BasicList) then
        h#"methods" = apply(toList h#"methods", projectMethod);
    if h#?"options" and instance(h#"options", BasicList) then
        h#"options" = projectOptions h#"options";
    new HashTable from h)

-- Machine reference fields come from the facts base (not the page), so they are
-- bare names; qualify them to the canonical $package$name key (matching the
-- round-tripped prose/see-also) using the facts index. Targets absent from the
-- corpus stay bare.
factsIndex = new MutableHashTable
packageIndex = new MutableHashTable
qualKey = nm -> if instance(nm, String) and factsIndex#?nm then "$" | factsIndex#nm#0 | "$" | nm else nm
qualPackageKey = nm -> if instance(nm, String) and packageIndex#?nm
    then "$" | packageIndex#nm | "$" | nm else qualKey nm
qualList = v -> if instance(v, BasicList) then apply(toList v, qualKey) else v
-- Scalar fields that name a documented object: `class` is a type, `package` is a
-- package, alongside `parent`/`typical_value`. All become $package$name keys so a
-- consumer can resolve them like any other reference (refName recovers the bare
-- name -- e.g. the package scope -- when needed).
scalarRefFields = {"parent", "typical_value", "class"}
machineRefFields = {"ancestors", "subtypes", "instances", "constructors", "common_operations"}
-- An option's documented type and the class of its default are references too.
-- A page may edit the documented type, so they are qualified after the overlay.
optionRefFields = {"valueType", "defaultType"}
qualifyOptions = os -> if not instance(os, BasicList) then os else apply(toList os, o ->
    if not instance(o, HashTable) then o else (
        oo := new MutableHashTable from o;
        scan(optionRefFields, f -> if oo#?f and instance(oo#f, String) then oo#f = qualKey oo#f);
        new HashTable from oo))
qualifyOptionRefs = rec -> (
    r := new MutableHashTable from rec;
    if r#?"options" then r#"options" = qualifyOptions r#"options";
    if r#?"methods" and instance(r#"methods", BasicList) then
        r#"methods" = apply(toList r#"methods", m ->
            if instance(m, HashTable) and m#?"options" then
                merge(m, hashTable {"options" => qualifyOptions m#"options"}, last)
            else m);
    new HashTable from r)
qualifyMachineRefs = rec -> (
    r := new MutableHashTable from rec;
    if r#?"source_location" and instance(r#"source_location", HashTable) then (
        location := new MutableHashTable from r#"source_location";
        if location#?"filename" and instance(location#"filename", String) then
            location#"filename" = toAbsolutePath location#"filename";
        r#"source_location" = new HashTable from location);
    scan(scalarRefFields, f -> if r#?f and instance(r#f, String) then r#f = qualKey r#f);
    if r#?"package" and instance(r#"package", String) then
        r#"package" = qualPackageKey r#"package";
    scan(machineRefFields, f -> if r#?f and instance(r#f, BasicList) then r#f = qualList r#f);
    if r#?"methods" and instance(r#"methods", BasicList) then
        r#"methods" = apply(toList r#"methods", m -> (
            if not instance(m, HashTable) then m else (
                mm := new MutableHashTable from m;
                if mm#?"source_location" and instance(mm#"source_location", HashTable) then (
                    location := new MutableHashTable from mm#"source_location";
                    if location#?"filename" and instance(location#"filename", String) then
                        location#"filename" = toAbsolutePath location#"filename";
                    mm#"source_location" = new HashTable from location);
                if mm#?"domain" and instance(mm#"domain", BasicList) then mm#"domain" = qualList mm#"domain";
                if mm#?"typicalValue" and instance(mm#"typicalValue", String) then mm#"typicalValue" = qualKey mm#"typicalValue";
                new HashTable from mm)));
    -- operator block carries reference keys in its assignment-form domains.
    if r#?"operator" and instance(r#"operator", HashTable) and r#"operator"#?"assignment" then (
        op := new MutableHashTable from r#"operator";
        op#"assignment" = apply(toList op#"assignment", a -> (
            if not instance(a, HashTable) then a else (
                aa := new MutableHashTable from a;
                if aa#?"domain" and instance(aa#"domain", BasicList) then aa#"domain" = qualList aa#"domain";
                new HashTable from aa)));
        r#"operator" = new HashTable from op);
    new HashTable from r)

-- ---------------------------------------------------------------------------
-- Main. Load the machine base, walk the pages, overlay, emit.
-- ---------------------------------------------------------------------------
-- Pages live under <package>/<kind>/<normalized>.md.
collectPages = dir -> flatten apply(
    select(readDirectory dir, e -> e =!= "." and e =!= ".."),
    e -> (
        p := dir | "/" | e;
        if isDirectory p then collectPages p
        -- SUMMARY.md is the nav file; _index.md are per-kind chapter parents
        -- (navigation only) -- neither is a documented object.
        else if match("\\.md$", e) and e =!= "SUMMARY.md" and e =!= "_index.md" then {p} else {}))

normalizedOf = path -> replace("\\.md$", "", last separate("/", path))
packageOf = (pagesDir, path) -> first separate("/", substring(#pagesDir + 1, path))

-- Overlay the pages below pagesDir on the records of the facts file factsPath;
-- write every field to referencePath and the LSP index to indexPath, its meta
-- record listing the packages defaultLoaded; the number of records.
assembleReference = (pagesDir, factsPath, referencePath, indexPath, defaultLoaded) -> (
    nowIso = replace("[[:space:]]+$", "", get "!date -u +%Y-%m-%dT%H:%M:%SZ");
    scan({factsIndex, packageIndex}, table -> scan(keys table, key -> remove(table, key)));
    factsByKey := new MutableHashTable;
    scan(lines get factsPath, line -> (
        if #line == 0 then return;
        rec := fromJSON line;
        if rec =!= null and rec#?"normalized_name" and rec#"normalized_name" =!= null then (
            nn := toString rec#"normalized_name";
            pk := if rec#?"package" and rec#"package" =!= null
                then refName(toString rec#"package") else "Core";
            factsByKey#(pk, nn) = rec;
            kd := if rec#?"kind" and rec#"kind" =!= null
                then toString rec#"kind" else "object";
            if kd == "package" then packageIndex#nn = pk;
            -- Bare machine references are ambiguous when packages export the same
            -- name. Prefer Core, matching runtime dictionary construction; otherwise
            -- retain the first deterministic package occurrence.
            if not factsIndex#?nn or pk == "Core" then
                factsIndex#nn = (pk, kd)
        )));
    pages := collectPages pagesDir;
    -- (package, normalized_name) -> rendered hover Markdown. Both coordinates are
    -- required because independent packages may export the same bare name.
    hoverByKey := new MutableHashTable;
    records := apply(pages, path -> (
        normalized := normalizedOf path;
        packageName := packageOf(pagesDir, path);
        identity := (packageName, normalized);
        hoverByKey#identity = hoverMarkdownFor path;
        human := parsePage(path, normalized);
        base := qualifyMachineRefs(if factsByKey#?identity then new HashTable from factsByKey#identity
            else new HashTable from {
                "normalized_name" => normalized,
                "kind" => "object",
                "package" => packageName
            });
        qualifyOptionRefs overlayRecord(base, human)));
    sorted := apply(sort apply(#records, i -> (
        rec := records#i;
        packageName := if rec#?"package" and rec#"package" =!= null
            then refName(toString rec#"package") else "Core";
        (ascii packageName, ascii toString rec#"normalized_name", i, rec)
    )), t -> t#3);
    -- Full corpus: JSON Lines (one record per line).
    fullO := openOut referencePath;
    scan(sorted, rec -> fullO << toJSON rec << endl);
    close fullO;
    -- Combined LSP index: JSONL. First line is the meta record (the default-loaded
    -- baseline); each subsequent line is one compressed CompiledObject with its
    -- rendered hover `markdown` attached (omitted when undocumented). Schema in
    -- m2-index.schema.json. The markdown is a prose string -- attached AFTER
    -- compression/qualification so the reference-qualification passes never touch it.
    typeO := openOut indexPath;
    typeO << toJSON(new HashTable from {"kind" => "meta", "default_loaded" => defaultLoaded}) << endl;
    scan(sorted, rec -> (
        compiled := compressRecord rec;
        nn := if compiled#?"normalized_name" then toString compiled#"normalized_name";
        packageName := if compiled#?"package" and compiled#"package" =!= null
            then refName(toString compiled#"package") else "Core";
        identity := (packageName, nn);
        md := if nn =!= null and hoverByKey#?identity then hoverByKey#identity;
        if md =!= null and md =!= "" then
            compiled = new HashTable from append(pairs compiled, "markdown" => md);
        typeO << toJSON compiled << endl));
    close typeO;
    stderr << "-- assembled " << toString(#sorted) << " records from " << pagesDir
        << " (base " << factsPath << ")"
        << " -> " << referencePath << " (full), " << indexPath << " (LSP index, " << #defaultLoaded << " default-loaded)" << endl;
    #sorted
)
