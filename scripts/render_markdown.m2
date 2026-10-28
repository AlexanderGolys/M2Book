-- jsonl -> per-page Markdown documentation.
--
-- The page is PURE Macaulay documentation: a human reads and edits it to fill
-- gaps (descriptions, examples, return types, the hand-filled `exact` flags,
-- tags). It carries NO internal bookkeeping -- normalized_name, last_update,
-- slug, extra_keys, source provenance and the raw doc-DB scrape never appear.
-- Those machine/provenance fields are restored on the reverse trip
-- (assemble_jsonl.m2) by overlaying the extraction corpus, so the docs stay
-- clean while the full JSON round-trips.
--
-- Every section uses a human title (## Description, ## Parameters, ...) rather
-- than a raw field key, and the inverse maps those titles back via a shared
-- registry. Cross-references render as Markdown links with de-normalized display
-- text and the normalized name as the target.
--
-- Usage:
--   M2 --script scripts/render_markdown.m2 [m2-facts.jsonl] [book/src]

needsPackage "JSON"
load "./load_package.m2"
importFrom("M2Book", {"normalizeName", "denormalizeName", "sourceFilePath", "capitalize"})

args = drop(scriptCommandLine, 1)
inputPath = if #args > 0 then args#0 else "m2-facts.jsonl"
outputDir = if #args > 1 then args#1 else "book/src"
if not isDirectory outputDir then makeDirectory outputDir

-- ---------------------------------------------------------------------------
-- Value helpers. fromJSON yields String / ZZ / RR / Boolean / Nothing / List /
-- HashTable.
-- ---------------------------------------------------------------------------
jstr = v -> (
    if v === null then ""
    else if instance(v, String) then v
    else if v === true then "true"
    else if v === false then "false"
    else toString v)

isBlankVal = v -> (
    v === null
    or (instance(v, String) and #v == 0)
    or (instance(v, BasicList) and #v == 0)
    or (instance(v, HashTable) and #v == 0))

get' = (h, k) -> if instance(h, HashTable) and h#?k then h#k else null

-- Empty *documentation* fields are surfaced with this marker rather than omitted,
-- so an editor sees the gap; the inverse treats it as "still empty". Structural /
-- introspected empties (methods, options, domains, hierarchy, slug, versions) are
-- never stamped -- their absence means "none" and they are already correct.
undocMarker = "_undocumented_"
isCallableKind = kind -> kind === "function" or kind === "operator"
stampSection = (key, kind) -> (
    key === "description" or key === "examples" or key === "see_also"
    or (isCallableKind kind and (key === "domainDescription" or key === "codomainDescription")))

-- Internal/provenance fields: never rendered. Restored from the corpus on
-- assembly (or regenerated). `name`/`brief` are rendered as title/lede, not as
-- sections, so they are excluded from the generic section pass too.
hiddenKeys = set {
    "normalized_name", "last_update", "slug", "extra_keys",
    "source_location", "doc_source", "doc_entries",
    "evaluatedOptions", "name", "brief"}

-- ---------------------------------------------------------------------------
-- Cross-reference rendering. A normalized name becomes a link whose display is
-- the de-normalized (human) spelling and whose target is `<normalized>.md`.
-- ---------------------------------------------------------------------------
-- Reference resolution. The canonical key is bare "Name" or qualified
-- "$Package$Name"; `refName` takes the name part. Pages live at
-- book/src/<package>/<kind>/<name>.md (depth 2), so "../../" reaches the root
-- from any page. We resolve the name's home package+kind from `refIndex` (built
-- in the main pass) and emit an mdbook relative .md link (mdbook rewrites
-- .md -> .html). Targets absent from the corpus fall back to a bare name.md
-- until their package is added. This is the mdbook link "flavor"; the same key
-- can render as an Obsidian [[wikilink]] later.
refIndex = new MutableHashTable
refName = key -> last separate("[$]", key)
resolveHref = name -> (
    if refIndex#?name then ("../../" | refIndex#name#0 | "/" | refIndex#name#1 | "/" | name | ".md")
    else name | ".md")
mdLink = key -> (n := refName key; "[" | denormalizeName n | "](" | resolveHref n | ")")
inlineCode = s -> "`" | s | "`"

sourceLocationText = record -> (
    location := get'(record, "source_location");
    if instance(location, HashTable) and sourceFilePath location#"filename" === null then return null;
    if instance(location, HashTable) then inlineCode concatenate(
        jstr location#"filename", ":", jstr location#"start_row", ":", jstr location#"start_col",
        "-", jstr location#"stop_row", ":", jstr location#"stop_col")
)

-- Prose is free text. Only `## ` and `### ` lines would be misread by the inverse
-- (section split / method split), so just those two levels are escaped; `#### `+
-- is safe (folded back as prose) and must stay a real heading for a promoted
-- `#### Caveat`. Applied AFTER caveat promotion. The inverse restores the escape.
escapeDangerous = s -> demark("\n", apply(separate("\n", s), l -> if match("^#{2,3}([^#]|$)", l) then "\\" | l else l))

-- $<normalized> inline link form (schema's prose link marker) -> Markdown link.
linkifyProse = s -> (
    result := ""; rest := s;
    while (m := regex(///\$<([^>]+)>///, rest)) =!= null do (
        whole := m#0; grp := m#1;
        result = result | substring(0, whole#0, rest) | mdLink substring(grp, rest);
        rest = substring(whole#0 + whole#1, rest));
    result | rest)

-- A mashed doc sub-section header (extraction artifact, e.g. "...given.### Caveat
-- If ...") is promoted to a real `#### Caveat` subheading so it renders as its
-- own section. Idempotent: the lookarounds skip an already-promoted `####`.
-- (Folded synopsis sections like Consequences are already emitted as clean
-- `#### Title` by the extractor, so they need no promotion here.)
caveatize = s -> replace(///(?<!#)###(?!#)[ \t]*Caveat///, "\n\n#### Caveat\n\n", s)

-- Prose for description-like fields: links, then caveat promotion, then escape
-- the still-dangerous `##`/`###` lines (the promoted `#### Caveat` is left alone).
-- Finally normalize blank runs (collapse 3+ newlines to one blank line; strip
-- leading/trailing blanks) so a re-render of the assembled corpus -- whose inverse
-- already trims prose -- reproduces the page exactly (round-trip idempotency).
-- strip leading/trailing blank lines without an anchored regex: Boost treats
-- ^/$ as multiline, so `^\n+|\n+$` would also eat blank lines BETWEEN paragraphs
-- (e.g. the gap after a promoted `#### Caveat`). Trim on the line list instead.
trimBlankEnds = s -> (
    ls := separate("\n", s);
    while #ls > 0 and match("^[ \t]*$", first ls) do ls = drop(ls, 1);
    while #ls > 0 and match("^[ \t]*$", last ls) do ls = drop(ls, -1);
    demark("\n", ls))
proseText = s -> trimBlankEnds replace(///\n{3,}///, "\n\n", escapeDangerous caveatize linkifyProse s)

-- ---------------------------------------------------------------------------
-- Section value renderers. Each returns the section body (already trailing \n).
-- ---------------------------------------------------------------------------
renderProse = v -> proseText jstr v | "\n\n"

renderRefList = v -> concatenate apply(toList v, e -> "- " | mdLink jstr e | "\n") | "\n"

renderPlainList = v -> concatenate apply(toList v, e -> "- " | jstr e | "\n") | "\n"

-- domainDescription: {paramName => prose}. Bullet per parameter.
renderParams = v -> concatenate apply(sort keys v,
    k -> "- **" | k | "** — " | linkifyProse jstr v#k | "\n") | "\n"

-- properties is a flag map {flag => ""}; show the present flags.
renderProperties = v -> renderPlainList keys v

-- An example renders as a macaulay2-fenced input block plus, when present, a
-- plain-fenced output block; the inverse pairs them back into [input, output].
renderExamples = v -> concatenate apply(toList v, ex -> (
    inp := if instance(ex, BasicList) and #ex >= 1 then jstr ex#0 else jstr ex;
    out := if instance(ex, BasicList) and #ex >= 2 then jstr ex#1 else "";
    s := "```macaulay2\n" | inp | "\n```\n";
    if #out > 0 then s = s | "\n```\n" | out | "\n```\n";
    s | "\n"))

-- One option: "- **Key** — desc (default: `d`, type: `t`, values: `a`, `b`)".
renderOption = o -> (
    -- An option key is a Symbol; link it to its page.
    line := "- **" | mdLink jstr get'(o, "key") | "**";
    desc := get'(o, "description");
    if not isBlankVal desc then line = line | " — " | linkifyProse jstr desc;
    quals := {};
    d := get'(o, "default");      if not isBlankVal d then quals = append(quals, "default: " | inlineCode jstr d);
    t := get'(o, "valueType");    if not isBlankVal t then quals = append(quals, "type: " | inlineCode jstr t);
    pv := get'(o, "possibleValues");
    if not isBlankVal pv then quals = append(quals, "values: " | demark(", ", apply(toList pv, e -> inlineCode jstr e)));
    if #quals > 0 then line = line | " (" | demark(", ", quals) | ")";
    line | "\n")

renderOptions = v -> concatenate apply(toList v, renderOption) | "\n"

renderOperator = v -> (
    s := "- **Token:** " | inlineCode jstr get'(v, "token") | "\n";
    forms := get'(v, "forms");
    if not isBlankVal forms then s = s | "- **Forms:** " | demark(", ", apply(toList forms, jstr)) | "\n";
    attrs := get'(v, "attributes");
    if instance(attrs, HashTable) then scan(sort keys attrs, fk -> (
        fv := attrs#fk;
        if not isBlankVal fv then
            s = s | "- **" | fk | " attributes:** " | demark(", ", apply(toList fv, jstr)) | "\n"));
    -- assignment form `x op y = z`: one bullet per typed installation, by operand domain.
    asg := get'(v, "assignment");
    if not isBlankVal asg then scan(toList asg, a -> (
        dom := get'(a, "domain");
        if not isBlankVal dom then
            s = s | "- **Assignment:** " | demark(", ", apply(toList dom, e -> mdLink jstr e)) | "\n"));
    s | "\n")

renderExports = v -> concatenate apply(
    {("functions", "Functions"), ("operators", "Operators"), ("types", "Types"), ("objects", "Objects")},
    grp -> (
        lst := get'(v, grp#0);
        if isBlankVal lst then "" else "### " | grp#1 | "\n\n" | renderRefList lst))

renderAuthors = v -> concatenate apply(toList v, a -> (
    if instance(a, HashTable) then (
        nm := jstr get'(a, "name");
        em := get'(a, "email");
        "- " | nm | (if not isBlankVal em then " (" | jstr em | ")" else "") | "\n")
    else "- " | jstr a | "\n")) | "\n"

renderValueString = v -> "```\n" | jstr v | "\n```\n\n"

-- ---------------------------------------------------------------------------
-- "See <ref>." lifting. A standalone sentence that is just a cross-reference
-- (sentence-initial "See"/"See also", one $<target>, ending in a period) is
-- moved out of the prose into see-also. Operates on the $<...> inline form,
-- before links are rendered. Returns (cleanedProse, {normalizedTargets}).
-- ---------------------------------------------------------------------------
liftSeeRefs = desc -> (
    targets := {}; rest := desc;
    re := ///(^|[.!?][[:space:]]+|\n[[:space:]]*)See( +also)?[[:space:]]+\$<([^>]+)>[[:space:]]*\.///;
    while (m := regex(re, rest)) =!= null do (
        targets = append(targets, substring(m#3, rest));
        rest = substring(0, (m#0)#0, rest) | substring(m#1, rest) | substring((m#0)#0 + (m#0)#1, rest));
    -- Only touch the prose when something was actually lifted, so unaffected
    -- descriptions pass through byte-for-byte.
    cleaned := if #targets == 0 then desc
        else replace("^[[:space:]]+|[[:space:]]+$", "", replace("[ \t][ \t]+", " ", rest));
    (cleaned, targets))

-- Apply liftSeeRefs to a record's description and to each method's description,
-- folding the lifted targets into the respective see_also lists.
liftRecordSeeRefs = rec -> (
    r := new MutableHashTable from rec;
    if instance(get'(rec, "description"), String) then (
        (cd, refs) := liftSeeRefs r#"description";
        r#"description" = cd;
        if #refs > 0 then r#"see_also" = sort unique join(toList (get'(rec, "see_also") ?? {}), refs));
    if instance(get'(rec, "methods"), BasicList) then
        r#"methods" = apply(toList r#"methods", m -> (
            if not instance(m, HashTable) then m else (
                mm := new MutableHashTable from m;
                if instance(get'(m, "description"), String) then (
                    (cd2, refs2) := liftSeeRefs mm#"description";
                    mm#"description" = cd2;
                    if #refs2 > 0 then mm#"see_also" = sort unique join(toList (get'(m, "see_also") ?? {}), refs2));
                new HashTable from mm)));
    new HashTable from r)

-- ---------------------------------------------------------------------------
-- ofClass inverse. M2 renders type references in synopses via `ofClass T`, whose
-- text is the type's `synonym` (ZZ -> "integer", List -> "list"), left QUOTED in
-- the scraped domain/codomain prose. We invert that: a quoted synonym becomes a
-- real reference $<Type>. The reverse map is collision-free, so each quoted
-- synonym names exactly one type. Built once by scanning loaded types.
-- ---------------------------------------------------------------------------
synonymToType = (
    allSyms := flatten apply(dictionaryPath, d -> values d);
    tys := unique select(apply(allSyms, s -> try value s else null), v -> instance(v, Type));
    m := new MutableHashTable;
    scan(tys, T -> (w := try T.synonym else null; if instance(w, String) then m#w = toString T));
    new HashTable from m)

-- Replace each quoted ofClass synonym ("list") with a reference ($<List>);
-- non-synonym quoted text is left untouched.
linkifySynonyms = s -> (
    result := ""; rest := s;
    while (mm := regex(///"([^"]+)"///, rest)) =!= null do (
        st := (mm#0)#0; ln := (mm#0)#1; w := substring(mm#1, rest);
        result = result | substring(0, st, rest) | (
            if synonymToType#?w then "$<" | normalizeName synonymToType#w | ">"
            else substring(st, ln, rest));
        rest = substring(st + ln, rest));
    result | rest)

-- Apply the synonym inverse to a record's domain/codomain prose (the synopsis-
-- derived fields), top-level and per method.
fixComponentProse = obj -> (
    o := new MutableHashTable from obj;
    dd := get'(obj, "domainDescription");
    if instance(dd, HashTable) then
        o#"domainDescription" = applyValues(dd, v -> if instance(v, String) then linkifySynonyms v else v);
    cd := get'(obj, "codomainDescription");
    if instance(cd, String) then o#"codomainDescription" = linkifySynonyms cd;
    new HashTable from o)

linkifyRecordSynonyms = rec -> (
    r := new MutableHashTable from fixComponentProse rec;
    if instance(get'(rec, "methods"), BasicList) then
        r#"methods" = apply(toList r#"methods", m -> if instance(m, HashTable) then fixComponentProse m else m);
    new HashTable from r)

-- The unique type named by a piece of (synonym-linkified) prose: the single
-- $<Type> reference it contains, or null when there are none or several. Used to
-- recover a return type from a codomain description that only gave prose.
recoverTypeFromProse = s -> (
    if not instance(s, String) then return null;
    targets := {}; rest := s;
    while (mm := regex(///\$<([^>]+)>///, rest)) =!= null do (
        targets = append(targets, substring(mm#1, rest));
        rest = substring((mm#0)#0 + (mm#0)#1, rest));
    u := unique targets;
    if #u == 1 then first u else null)

-- Fill return types from documentation. The function's return type is its own
-- typical_value, else the unique type named by its codomain prose. A method's
-- return type is its own typicalValue (from M2, authoritative), else its own
-- codomain prose, else the function's — so a documented single return propagates
-- to overloads M2 left untyped (e.g. about(Symbol) inherits NumberedVerticalList).
propagateReturnTypes = rec -> (
    r := new MutableHashTable from rec;
    funcReturn := if not isBlankVal get'(rec, "typical_value") then jstr rec#"typical_value"
        else recoverTypeFromProse get'(rec, "codomainDescription");
    if funcReturn =!= null and isBlankVal get'(rec, "typical_value") then r#"typical_value" = funcReturn;
    if instance(get'(rec, "methods"), BasicList) then
        r#"methods" = apply(toList r#"methods", m -> (
            if not instance(m, HashTable) then m else (
                mm := new MutableHashTable from m;
                if isBlankVal get'(m, "typicalValue") then (
                    mr := recoverTypeFromProse get'(m, "codomainDescription");
                    if mr =!= null then mm#"typicalValue" = mr
                    -- inherited from the function's global return; flag it as less
                    -- certain than the method's own (M2-installed) return type.
                    else if funcReturn =!= null then (
                        mm#"typicalValue" = funcReturn; mm#"returnInherited" = true));
                new HashTable from mm)));
    new HashTable from r)

-- ---------------------------------------------------------------------------
-- Method blocks. Title by operator form when present, else by signature name.
-- Domain comes from the corpus on assembly, but is shown for the reader.
-- ---------------------------------------------------------------------------
methodTitle = m -> (
    form := get'(m, "form");
    if not isBlankVal form then capitalize jstr form | " form"
    else inlineCode denormalizeName jstr get'(m, "name"))

methodFacts = (m, unitName) -> (
    facts := {};
    location := sourceLocationText m;
    if location =!= null then facts = append(facts, "- **Defined at:** " | location);
    dom := get'(m, "domain");
    if not isBlankVal dom then
        facts = append(facts, "- **Domain:** " | demark(", ", apply(toList dom, e -> mdLink jstr e)));
    tv := get'(m, "typicalValue");
    if not isBlankVal tv then (
        quals := {};
        -- Always state where the return type came from: "common typical value"
        -- means the function-level value was inherited; "this method/signature"
        -- means the nested callable record supplies it directly.
        quals = append(quals,
            if get'(m, "returnInherited") === true then "common typical value"
            else "this " | unitName);
        if get'(m, "exact") === true then quals = append(quals, "exact");
        facts = append(facts, "- **Returns:** " | mdLink jstr tv | " (" | demark(", ", quals) | ")"))
    else facts = append(facts, "- **Returns:** " | undocMarker);
    ar := get'(m, "arity");    if not isBlankVal ar then facts = append(facts, "- **Arity:** " | jstr ar);
    sd := get'(m, "side");     if not isBlankVal sd then facts = append(facts, "- **Side:** " | jstr sd);
    if get'(m, "flexible") === true then facts = append(facts, "- **Flexible:** yes");
    -- Undocumented prose slots listed as labeled bullets (documented ones render
    -- as the blockquote brief / prose description / #### subsections below).
    if isBlankVal get'(m, "brief") then facts = append(facts, "- **Brief:** " | undocMarker);
    if isBlankVal get'(m, "description") then facts = append(facts, "- **Description:** " | undocMarker);
    if isBlankVal get'(m, "examples") then facts = append(facts, "- **Examples:** " | undocMarker);
    if #facts == 0 then "" else demark("\n", facts) | "\n\n")

-- The definition's source code, as a fenced M2 block (machine-provided; shown for
-- reference, not editable -- the inverse ignores it).
renderSource = v -> "```m2\n" | jstr v | "\n```\n\n"

-- Aliases: the other names that resolve to this object, as an inline-code list.
renderAliases = v -> demark(", ", apply(toList v, e -> inlineCode jstr e)) | "\n\n"

-- A method's brief is a blockquote tagline so the inverse can tell it from the
-- (also prose) description that follows.
renderBlockquote = s -> concatenate apply(separate("\n", jstr s), l -> "> " | l | "\n") | "\n"

renderCallableDetail = (m, unitName) -> (
    s := "### " | methodTitle m | "\n\n" | methodFacts(m, unitName);
    br := get'(m, "brief");          if not isBlankVal br then s = s | renderBlockquote br;
    de := get'(m, "description");    if not isBlankVal de then s = s | proseText jstr de | "\n\n";
    dd := get'(m, "domainDescription"); if not isBlankVal dd then s = s | "#### Parameters\n\n" | renderParams dd;
    cd := get'(m, "codomainDescription"); if not isBlankVal cd then s = s | "#### Returns\n\n" | renderProse cd;
    op := get'(m, "options");        if not isBlankVal op then s = s | "#### Options\n\n" | renderOptions op;
    exs := get'(m, "examples");      if not isBlankVal exs then s = s | "#### Examples\n\n" | renderExamples exs;
    source := get'(m, "source");     if not isBlankVal source then s = s | "#### Source\n\n" | renderSource source;
    sa := get'(m, "see_also");       if not isBlankVal sa then s = s | "#### See also\n\n" | renderRefList sa;
    s)

renderMethod = m -> renderCallableDetail(m, "method")
renderSignature = m -> renderCallableDetail(m, "signature")

-- When there are several methods, list every signature up front as a quick
-- index, then the detailed blocks. The index sits before the first `###`, so the
-- inverse (which only reads the per-method `###` blocks) ignores it.
-- mdbook derives a heading's anchor id by keeping alphanumerics / space / - / _,
-- lowercasing, and turning spaces into hyphens (backticks and other punctuation
-- dropped). We replicate it so the short index can link to each detail block.
mdSlug = s -> replace(" ", "-", replace("[^a-z0-9 _-]", "", toLower replace("`", "", s)))

-- Short index: one linked signature per method, jumping to its detail block below.
renderMethodIndex = v -> concatenate apply(toList v, m -> (
    t := methodTitle m; "- [" | t | "](#" | mdSlug t | ")\n")) | "\n"

-- Detail blocks (the part the inverse parses). Lives in its own section near the
-- page bottom; the index above links here.
renderMethodDetails = v -> concatenate apply(toList v, renderMethod)
renderSignatureDetails = v -> concatenate apply(toList v, renderSignature)

-- ---------------------------------------------------------------------------
-- Page assembly. Identity facts sit under the lede; the rest are `##` sections
-- in a fixed, readable order. Sections are emitted only when non-blank.
-- ---------------------------------------------------------------------------
-- Identity facts, in order: (jsonKey, Label, kind-of-value).
identityFacts = rec -> (
    facts := {};
    add := (label, txt) -> facts = append(facts, "- **" | label | ":** " | txt);
    kind := jstr get'(rec, "kind");
    callable := isCallableKind kind;
    -- `kind` is our internal classification (no M2 meaning), so it is not shown.
    if not isBlankVal get'(rec, "package") then add("Package", mdLink jstr rec#"package");
    if not isBlankVal get'(rec, "version") then add("Version", jstr rec#"version");
    if not isBlankVal get'(rec, "class") then add("Class", mdLink jstr rec#"class");
    scan({("protected", "Protected"), ("mutable", "Mutable")}, (key, label) ->
        if rec#?key and rec#key =!= null then add(label, jstr rec#key));
    location := sourceLocationText rec;
    if location =!= null then add("Defined at", location);
    if not isBlankVal get'(rec, "parent") then add("Parent", mdLink jstr rec#"parent");
    if not isBlankVal get'(rec, "typical_value") then add("Result type", mdLink jstr rec#"typical_value")
    else if kind === "function" then add("Result type", undocMarker);
    al := get'(rec, "aliases");
    if not isBlankVal al then add("Aliases", demark(", ", apply(toList al, e -> inlineCode jstr e)));
    -- Documentation slots: a documented one renders as a section below; an
    -- undocumented one is listed here as a labeled bullet, never an empty heading.
    docGap := (label, key, applies) -> if applies and isBlankVal get'(rec, key) then add(label, undocMarker);
    docGap("Brief", "brief", true);
    docGap("Description", "description", true);
    docGap("Parameters", "domainDescription", callable);
    docGap("Returns", "codomainDescription", callable);
    docGap("Examples", "examples", true);
    docGap("See also", "see_also", true);
    if #facts == 0 then "" else demark("\n", facts) | "\n\n")

-- (jsonKey, Section Title, rendererFn). Order defines page layout.
sectionSpecs = {
    ("description", "Description", renderProse),
    ("domainDescription", "Parameters", renderParams),
    ("codomainDescription", "Returns", renderProse),
    ("operator", "Operator", renderOperator),
    ("options", "Options", renderOptions),
    ("methods", "Methods", renderMethodIndex),
    ("ancestors", "Ancestors", renderRefList),
    ("subtypes", "Subtypes", renderRefList),
    ("instances", "Instances", renderRefList),
    ("constructors", "Constructors", renderRefList),
    ("common_operations", "Common operations", renderRefList),
    ("authors", "Authors", renderAuthors),
    ("exports", "Exports", renderExports),
    ("value_string", "Value", renderValueString),
    ("examples", "Examples", renderExamples),
    ("source", "Source", renderSource),
    ("properties", "Properties", renderProperties),
    ("tags", "Tags", renderPlainList),
    -- Detail blocks live near the bottom, just before See also; the index above
    -- links into them. Plain functions relabel these two sections as Signatures
    -- because their static call signatures are not M2 method installations.
    ("methods", "Method details", renderMethodDetails),
    ("see_also", "See also", renderRefList)}

-- jsonKeys handled by identity facts or title/lede; not repeated as sections.
factKeys = set {"kind", "package", "version", "class", "parent", "typical_value", "aliases", "protected", "mutable"}

-- Space is expensive: drop the blank line(s) immediately after any heading so the
-- content sits right under it. Fence-aware (leaves code blocks alone) and idempotent
-- (a heading already followed by content is untouched), so the inverse round-trips.
compactHeadings = page -> (
    inFence := false; prevHeading := false; out := {};
    scan(separate("\n", page), ln -> (
        if match("^```", ln) then (inFence = not inFence; out = append(out, ln); prevHeading = false)
        else if inFence then (out = append(out, ln); prevHeading = false)
        else if prevHeading and match("^[[:space:]]*$", ln) then null
        else (out = append(out, ln); prevHeading = match("^#{1,6} ", ln))));
    demark("\n", out))

renderRecordMd = rec -> (
    nm := jstr get'(rec, "name");
    kind := jstr get'(rec, "kind");
    body := "# " | nm | "\n\n";
    br := get'(rec, "brief");
    if not isBlankVal br then body = body | linkifyProse jstr br | "\n\n";
    body = body | identityFacts rec;
    -- Documented sections only; undocumented slots are the labeled bullets above.
    compactHeadings(body | concatenate apply(sectionSpecs, spec -> (
        key := spec#0; v := get'(rec, key);
        title := spec#1;
        if kind === "function" and key === "methods" then
            title = if title === "Methods" then "Signatures" else "Signature details";
        renderer := if title === "Signature details" then renderSignatureDetails else spec#2;
        if not isBlankVal v then "## " | title | "\n\n" | renderer v else ""))))

-- ---------------------------------------------------------------------------
-- Main: read jsonl, write one page per record under <package>/<kind>/, then a
-- grouped SUMMARY.md matching the on-disk layout.
-- ---------------------------------------------------------------------------
isMarkdownSafe = name -> not match("[\\[\\](){}]", name) and #name > 1 and name =!= "print"
reservedNames = {"toc", "404"}
parsedRecs = select(apply(lines get inputPath, line -> if #line == 0 then null else fromJSON line), r -> r =!= null)
-- First pass: reference index name -> (package, kind), so links resolve to paths.
scan(parsedRecs, r -> (
    nm := if not isBlankVal get'(r, "normalized_name") then jstr r#"normalized_name" else jstr get'(r, "name");
    -- `package` may be a $package$name reference key in the assembled corpus; the
    -- directory is the bare package name (refName recovers it; a no-op on bare input).
    pk := if not isBlankVal get'(r, "package") then refName jstr r#"package" else "Core";
    kd := if not isBlankVal get'(r, "kind") then jstr r#"kind" else "object";
    if not member(nm, reservedNames) then refIndex#nm = (pk, kd)))
-- Second pass: render each page.
records = new MutableList
scan(parsedRecs, rec0 -> (
    rec := propagateReturnTypes linkifyRecordSynonyms liftRecordSeeRefs rec0;
    normalized := if not isBlankVal get'(rec, "normalized_name") then jstr rec#"normalized_name" else jstr get'(rec, "name");
    if member(normalized, reservedNames) then return;
    name := jstr get'(rec, "name");
    kind := if not isBlankVal get'(rec, "kind") then jstr rec#"kind" else "object";
    pkg := if not isBlankVal get'(rec, "package") then refName jstr rec#"package" else "Core";
    relPath := pkg | "/" | kind | "/" | normalized | ".md";
    pageDir := outputDir | "/" | pkg | "/" | kind;
    if not isDirectory pageDir then makeDirectory pageDir;
    out := openOut(outputDir | "/" | relPath);
    out << renderRecordMd rec;
    close out;
    records#(#records) = (name, normalized, kind, pkg, relPath)))

kindOrder = {"function", "methodFunction", "type", "operator", "package", "symbol", "table", "object"}
kindTitle = kind -> (
    if kind == "function" then "Functions"
    else if kind == "methodFunction" then "Method functions"
    else if kind == "type" then "Types"
    else if kind == "operator" then "Operators"
    else if kind == "package" then "Packages"
    else if kind == "symbol" then "Symbols"
    else if kind == "table" then "Tables"
    else "Objects")

summary = openOut(outputDir | "/SUMMARY.md")
summary << "# Macaulay2 Reference\n\n"
summary << "- [All objects](all/_index.md)\n\n"
byPkg = new MutableHashTable
scan(toList records, rec -> (
    pkg := rec#3;
    if not byPkg#?pkg then byPkg#pkg = new MutableList;
    byPkg#pkg#(#(byPkg#pkg)) = rec))
-- Markdown link text must not contain unescaped [ ] or \ (they break `[text]`).
escapeLinkText = s -> replace(///([][\\])///, ///\\$1///, s)
-- Chapter structure: a part-title per package, then one CLICKABLE chapter per
-- kind (a generated `_index.md` overview page) with that kind's pages NESTED
-- under it. mdbook requires a nested chapter's parent to be a real hyperlink, so
-- the per-kind index page is what makes the tree (top level collapses to a
-- handful of groups instead of 1000+ flat chapters).
navLabel = rec -> escapeLinkText denormalizeName rec#1
-- Flat "All objects" index page: every object, grouped by kind, alphabetical. A
-- browse / Ctrl-F surface reached from one top-level SUMMARY entry (no sidebar tree).
-- Named _index.md so assemble's collectPages skips it (navigation, not an object).
allDir = outputDir | "/all"
if not isDirectory allDir then makeDirectory allDir
allOut = openOut(allDir | "/_index.md")
allOut << "# All objects\n\n"
byKindAll = new MutableHashTable
scan(toList records, rec -> (
    k := rec#2;
    if not byKindAll#?k then byKindAll#k = new MutableList;
    byKindAll#k#(#(byKindAll#k)) = rec))
scan(kindOrder, kind -> (
    if byKindAll#?kind then (
        allOut << "## " << kindTitle kind << "\n\n";
        scan(sort toList toList byKindAll#kind, rec ->
            allOut << "- [" << navLabel rec << "](../" << rec#4 << ")\n");
        allOut << "\n")))
close allOut
scan(sort keys byPkg, pkg -> (
    summary << "# " << pkg << "\n\n";
    byKind := new MutableHashTable;
    scan(toList byPkg#pkg, rec -> (
        k := rec#2;
        if not byKind#?k then byKind#k = new MutableList;
        byKind#k#(#(byKind#k)) = rec));
    scan(kindOrder, kind -> (
        if byKind#?kind then (
            members := select(sort toList toList byKind#kind, rec -> rec#1 =!= "print");
            -- per-kind overview page (the clickable nesting parent)
            idxRel := pkg | "/" | kind | "/_index.md";
            idxDir := outputDir | "/" | pkg | "/" | kind;
            if not isDirectory idxDir then makeDirectory idxDir;
            idxOut := openOut(outputDir | "/" | idxRel);
            idxOut << "# " << kindTitle kind << " — " << pkg << "\n\n";
            scan(members, rec -> idxOut << "- [" << navLabel rec << "](" << rec#1 << ".md)\n");
            close idxOut;
            -- SUMMARY: clickable kind chapter, pages nested under it
            summary << "- [" << kindTitle kind << "](" << idxRel << ")\n";
            scan(members, rec -> summary << "  - [" << navLabel rec << "](" << rec#4 << ")\n");
            summary << "\n")))))
close summary
stderr << "-- wrote " << #toList records << " pages to " << outputDir << endl
