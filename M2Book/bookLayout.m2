-- The book layout. Every method a package shows, documented or not, is a chapter
-- of its function's page, and every exported symbol without documentation has a
-- page of its own; links point at those chapters and pages. mdBookPage is the
-- page showing a key, writeMdBook the pages of a package.

coreInternal := name -> value Core#"private dictionary"#name
getPrimaryTag := coreInternal "getPrimaryTag"
fixup := coreInternal "fixup"
toFilename := coreInternal "toFilename"
isMissingDoc := coreInternal "isMissingDoc"
isUndocumented := coreInternal "isUndocumented"

-- The package directories, links and pages of MarkdownDocs, which this layout extends.
markdownDocsInternal := name -> value MarkdownDocs#"private dictionary"#name
documentationPage := markdownDocsInternal "documentationPage"
onlinePage := markdownDocsInternal "onlinePage"
plainText := markdownDocsInternal "plainText"
noteCallout := markdownDocsInternal "noteCallout"
packageRawDocumentation := markdownDocsInternal "packageRawDocumentation"
packageSymbolTags := markdownDocsInternal "packageSymbolTags"
packageTags := markdownDocsInternal "packageTags"
packageDirectoryOptions := markdownDocsInternal "packageDirectoryOptions"
writePackageDirectory := markdownDocsInternal "writePackageDirectory"
-- the keys of a layout, as writePackageDirectory takes it
Documents := markdownDocsInternal "Documents"
PageOf := markdownDocsInternal "PageOf"
OutlineOrder := markdownDocsInternal "OutlineOrder"
ExtraPages := markdownDocsInternal "ExtraPages"
Sections := markdownDocsInternal "Sections"
SectionOf := markdownDocsInternal "SectionOf"

-----------------------------------------------------------------------------
-- The keys documented on a node
-----------------------------------------------------------------------------

loadedPackage := pkgname -> (
    found := select(loadedPackages, pkg -> pkg#"pkgname" === pkgname);
    if #found > 0 then
        first found
)

-- package name => (format of a primary tag => the other tags documented on its node)
secondaryTagsCache := new MutableHashTable

-- The tags documented on the node of a primary tag besides its own, when its
-- package is loaded; their raw documentation's tags, as a key of a package's raw
-- documentation may not make a tag again in this session.
secondaryTags := primary -> (
    if not secondaryTagsCache#?(primary.Package) then
        secondaryTagsCache#(primary.Package) = (
            pkg := loadedPackage primary.Package;
            if pkg === null then
                new HashTable
            else applyValues(partition(rawdoc -> format rawdoc.PrimaryTag,
                select(packageRawDocumentation pkg, rawdoc -> rawdoc#?PrimaryTag)),
                rawdocs -> apply(rawdocs, rawdoc -> rawdoc.DocumentTag))
        );
    tagsByPrimary := secondaryTagsCache#(primary.Package);
    if tagsByPrimary#?(format primary) then
        tagsByPrimary#(format primary)
    else {}
)

-----------------------------------------------------------------------------
-- The book layout: where a key is shown
-----------------------------------------------------------------------------

-- The tag of the documentation node holding a tag; a package's top node is its own.
primaryTag := tag -> if tag.Format != tag.Package then getPrimaryTag fixup tag else tag

-- An installed method's key is a Sequence, its function first; a method key is
-- one key.
isMethodKey := method(Dispatch => Thing)
isMethodKey Thing := key -> false
isMethodKey Sequence := key -> true

-- An overview's key is its title; it has no page without documentation.
isOverviewKey := method(Dispatch => Thing)
isOverviewKey Thing := key -> false
isOverviewKey String := key -> true

-- Core's code is documented by Macaulay2Doc.
documentingPackage := pkgname -> if pkgname === "Core" then "Macaulay2Doc" else pkgname

-- Where the code of a method is defined, or null for compiled code.
methodSource := methodKey -> (
    code := lookup methodKey;
    if code =!= null then
        locate code
)

-- The package whose files define a method: its source file, or a file of its
-- auxiliary directory; Core for compiled code and for Core's own files.
installingPackage := methodKey -> (
    source := methodSource methodKey;
    if source === null then
        return "Core";
    file := toAbsolutePath source#0;
    owners := select(loadedPackages, pkg -> pkg#?"source file" and (
        sourceFile := toAbsolutePath pkg#"source file";
        file === sourceFile or match("\\A" | regexQuote replace("\\.m2\\z",
            "/", sourceFile), file)
    ));
    if #owners > 0 then
        (first owners)#"pkgname"
    else "Core"
)

-- The package showing a method (a tag): the package documenting it, or else the
-- one installing it.
methodPackage := tag -> documentingPackage(
    if documentationPage tag =!= null then (primaryTag tag).Package else installingPackage tag.Key)

-- The page (package, page name) holding a method's chapter: the page of its
-- function in the method's package, or else a page named after the function,
-- made there.
methodPage := tag -> (
    pkgname := methodPackage tag;
    functionTag := makeDocumentTag first tag.Key;
    functionPage := documentationPage functionTag;
    if functionPage =!= null and functionPage#0 === pkgname then
        functionPage
    else (pkgname, toFilename format functionTag)
)

-- A method node shown as a chapter of its function's page, not as a page of its own.
isChapterNode = tag -> isMethodKey tag.Key and methodPage tag =!=
    documentationPage tag

-- Package, page and heading where the book layout shows a key (a tag): a method
-- in its chapter; another key on its node's page, or in its node's chapter; a
-- symbol without documentation on a page of its own in its package. The heading
-- is null for a page; the location is null for a key that is not shown.
bookLocation = tag -> (
    if isMethodKey tag.Key then
        return append(methodPage tag, format tag);
    if isUndocumented tag then
        return null;
    page := documentationPage tag;
    if page === null then
        return if not isOverviewKey tag.Key then (
            documentingPackage tag.Package, toFilename format tag, null
        );
    primary := primaryTag tag;
    if isChapterNode primary then
        append(methodPage primary, format primary)
    else append(page, null)
)

-- The identifier mdBook and GitHub give a heading: its letters and digits in
-- lower case, with - and _, whitespace as -, other characters dropped.
headingIdentifier := text -> replace(///\s///, "-", toLower replace(
    ///[^\w\s-]///, "", text
))

-- A link target's location; an installed page named by its path is a page of its own.
targetLocation := method()
targetLocation Sequence := page -> append(page, null)
targetLocation DocumentTag := bookLocation

-- A link target's page on the Macaulay2 website, or null.
targetWebsitePage := method()
targetWebsitePage Sequence := identity
targetWebsitePage DocumentTag := documentationPage

-- A link's text, as code when it is the name of its target.
targetName := method()
targetName Sequence := page -> null
targetName DocumentTag := format
linkText := (target, text) -> if text === {targetName target} then {MdCode first text} else text

-- The book layout's ResolveLink: a target shown in a linked package is linked at
-- its page, and at its heading when it is a chapter; any other target at its page
-- on the website. Link text naming the target is code.
resolveBookLink = (link, linked, style, sourcePackage) -> (
    target := first link;
    text := linkText(target, drop(toList link, 1));
    location := targetLocation target;
    if location =!= null and (linked === true or member(location#0, linked)) then (
        (pkgname, page, heading) := location;
        if style === "wikilink" then
            Wikilink prepend(
                concatenate(pkgname, "/", page, if heading =!= null then ("#",
                    heading)), text
            )
        else if style === "markdown" then
            MdLink prepend(concatenate(
                if pkgname =!= sourcePackage then ("../", pkgname, "/"), page, ".md",
                if heading =!= null then ("#", headingIdentifier heading)
            ), text)
        else error("M2Book: unknown LinkStyle ", toString style)
    ) else (
        website := targetWebsitePage target;
        if website === null then
            new MarkdownInline from append(text, " (missing documentation)")
        else MdLink prepend(onlinePage(website#0, website#1), text)
    )
)

-----------------------------------------------------------------------------
-- The book layout: pages
-----------------------------------------------------------------------------

-- The tag documented on a node (a primary tag) that formats as a text, or null.
nodeTagFormatted := (primary, text) -> (
    found := select(prepend(primary, secondaryTags primary), tag -> format tag === text);
    if #found > 0 then
        first found
)

-- Help's hypertext of a node (a primary tag) for the book layout. A key listed as
-- "f(X) -- see node" is a link of its own, to its chapter or to its node, and on
-- the node's page a key of the node listed as code links to its chapter.
bookMarkup := method()
bookMarkup (Thing, DocumentTag) := (x, primary) -> x
bookMarkup (Hypertext, DocumentTag) := (x, primary) -> new class x from apply(
    toList x, e -> bookMarkup(e, primary)
)
bookMarkup (SPAN, DocumentTag) := (x, primary) -> (
    entry := toList x;
    key := if #entry == 3 and instance(entry#0, KBD) and entry#1 ===
        " -- see " and instance(entry#2, TOH) then
        nodeTagFormatted(primaryTag entry#2#0, plainText entry#0);
    if key =!= null then
        TOH {key}
    else new SPAN from apply(entry, e -> bookMarkup(e, primary))
)
bookMarkup (KBD, DocumentTag) := (x, primary) -> (
    key := nodeTagFormatted(primary, plainText x);
    if key =!= null and isMethodKey key.Key then
        TO {key}
    else x
)

-- The name of a key of a node besides the primary one when it names another
-- object, not a method, an optional input or an overview, or null. The raw
-- documentation of an installed package keeps such a key as the symbol's name.
aliasName := method(Dispatch => Thing)
aliasName Thing := key -> toString key
aliasName String := key -> if isGlobalSymbol key then key
aliasName Sequence :=
aliasName Array :=
aliasName Option := Nothing => key -> null

-- Hypertext contents, without attributes.
hypertextContents := x -> select(deepSplice toList x, e -> not instance(e, Option))

-- The hypertext within x satisfying a predicate, outermost first.
hypertextSelect := (x, predicate) -> (
    if predicate x then {x}
    else if instance(x, Hypertext) then flatten apply(toList x, e -> hypertextSelect(e, predicate))
    else {}
)

-- A section of help's page: a DIV headed by a HEADER2 with a title isTitle accepts.
isSection := isTitle -> x -> instance(x, DIV) and any(hypertextContents x, e ->
    instance(e, HEADER2) and isTitle plainText e)

-- The titles of the sections of help's pages the book shows otherwise: the class
-- from "For the programmer" in the details, the citation at the end, and the
-- methods "Ways to use" lists as the chapters of the page.
isProgrammerTitle := title -> title === "For the programmer"
isCitationTitle := title -> title === "Citation"
isWaysToUseTitle := title -> match("\\AWays to use ", title)

-- Hypertext without the sections with a title isTitle accepts.
withoutSection := method()
withoutSection (Thing, Function) := (x, isTitle) -> x
withoutSection (Hypertext, Function) := (x, isTitle) -> new class x from apply(
    select(toList x, e -> not (isSection isTitle) e), e -> withoutSection(e, isTitle))

-- The class of an object as "For the programmer" says it, such as "a method
-- function", or null.
programmerClass := body -> (
    sections := hypertextSelect(body, isSection isProgrammerTitle);
    paragraphs := if #sections > 0 then select(hypertextContents first sections, e -> instance(e, PARA)) else {};
    entries := if #paragraphs > 0 then hypertextContents first paragraphs else {};
    is := position(entries, e -> e === " is ");
    if is =!= null then SPAN take(entries, {is + 1, #entries - 2})
)

-- A synopsis item of help (an LI) as (title, contents) when it lists inputs,
-- optional inputs or outputs, which the details show; null otherwise.
synopsisDetail := item -> (
    entries := hypertextContents item;
    title := if #entries > 0 then plainText first entries;
    if title === "Inputs:" or title === "Outputs:" then (replace(":", "", title), drop(entries, 1))
    else if title === "Optional inputs" then (title, drop(entries, 2))
)

-- A synopsis item naming a method's function, which the book does not show: the
-- method's chapter is on the function's page.
isFunctionItem := item -> match(///\A(Function|Operator|Scripted functor): ///, plainText item)

-- The object a key documents: a symbol's value; the raw documentation of an
-- installed package keeps a symbol's key as its name.
keyObject := method(Dispatch => Thing)
keyObject Thing := identity
keyObject Symbol := value
keyObject String := key -> if isGlobalSymbol key then value getGlobalSymbol key else key

-- A type's chain of ancestors, the type first, as the centered line below its
-- title, in place of its class: Graph ← Digraph ← HashTable ← Thing, each linked
-- to its page, spaced apart. Nothing for any other object; an object is one key.
ancestorSeparator := new MarkdownInline from "&ensp;←&ensp;"
ancestorsLine := method(Dispatch => Thing)
ancestorsLine Thing := x -> {}
ancestorsLine Type := type -> {
    MdParagraph MdHTML "<div align=\"center\">",
    MdParagraph between(ancestorSeparator,
        apply(ancestors type, ancestor -> MdDocLink {makeDocumentTag ancestor, MdCode toString ancestor})),
    MdParagraph MdHTML "</div>"}

-- A heading naming a key's object, its name as code; an overview's title, or a
-- package's name, as prose. An object is one key.
isCodeTitle := method(Dispatch => Thing)
isCodeTitle Thing := object -> true
isCodeTitle String :=
    isCodeTitle Package := object -> false
objectHeading := (level, key, name) -> MdHeading(level, if isCodeTitle keyObject key then MdCode name else name)

-- The package an object belongs to; an overview, named by a string, belongs to none.
objectPackage := method(Dispatch => Thing)
objectPackage Thing := package
objectPackage String := key -> null

-- The detail naming the package a key's object belongs to, when that is not the
-- package documenting it (a package name; Core is documented by Macaulay2Doc).
packageFacts := (key, pkgname) -> (
    owner := objectPackage keyObject key;
    if owner === null or documentingPackage owner#"pkgname" === pkgname then {}
    else {("Package", {MdCode owner#"pkgname"})}
)

-- The details section: a list of facts, each a label and its value, the value a
-- list of inline elements or of blocks.
detailsSection := facts -> if #facts == 0 then {} else {MdHeading(2, "Details"),
    MdList apply(facts, (label, value) -> prepend(MdStrong(label | ":"), prepend(" ", value)))}

-- file:line of a source position.
sourceText := source -> concatenate(baseFilename source#0, ":", toString source#1)

-- Blocks with every heading a number of levels deeper, or higher for a negative
-- number: a method's page as a chapter of another page is one level deeper.
shiftHeadings := method()
shiftHeadings (Thing, ZZ) := (x, levels) -> x
shiftHeadings (List, ZZ) := shiftHeadings (MdDocument, ZZ) := (blocks, levels) ->
    apply(blocks, block -> shiftHeadings(block, levels))
shiftHeadings (MdHeading, ZZ) := (heading, levels) -> MdHeading prepend(heading#0 + levels, drop(toList heading, 1))

-- A node's page in the book layout, and apart from it the footer the page shows
-- at its bottom. Under its title and headline the details: the class of the
-- object, its aliases, inputs and outputs; "For the programmer" and "Ways to use"
-- are left out, and the citation is moved to the end.
bookNode := primary -> (
    body := bookMarkup(help primary, primary);
    children := hypertextContents body;
    if #children == 0 or not instance(first children, HEADER1) then
        return (markdown body, {});
    heading := toList first children;
    description := replace(///\A -- ///, "", concatenate apply(drop(heading, 1), plainText));
    rest := drop(children, 1);
    synopsis := if #rest > 0 and instance(first rest, UL) then hypertextContents first rest else {};
    if #synopsis > 0 then rest = drop(rest, 1);
    details := select(apply(synopsis, synopsisDetail), detail -> detail =!= null);
    usage := select(synopsis, item -> synopsisDetail item === null and not isFunctionItem item);
    -- the footer: what follows the rule closing help's page
    closing := if #rest > 0 then hypertextContents last rest else {};
    rule := position(closing, e -> instance(e, HR));
    footer := if rule =!= null then drop(closing, rule + 1) else {};
    if rule =!= null then rest = append(drop(rest, -1), DIV take(closing, rule));
    citations := hypertextSelect(DIV rest, isSection isCitationTitle);
    class' := programmerClass DIV rest;
    rest = apply(rest, e -> fold({isProgrammerTitle, isCitationTitle, isWaysToUseTitle},
            e, (isTitle, section) -> withoutSection(section, isTitle)));
    aliases := select(apply(secondaryTags primary, tag -> aliasName tag.Key), name -> name =!= null);
    ancestry := ancestorsLine keyObject primary.Key;
    facts := join(
        if class' =!= null and #ancestry == 0 then {("Class", {markdown class'})} else {},
        packageFacts(primary.Key, primary.Package),
        if #aliases > 0 then {("Aliases", between(", ", apply(aliases, name -> MdCode name)))} else {},
        apply(details, (title, entries) -> (title, {markdown entries})));
    page := documentationPage primary;
    (MdDocument join({objectHeading(1, primary.Key, first heading)},
            ancestry,
            if description == "" then {} else {noteCallout description},
            detailsSection facts,
            if #usage > 0 then {shiftHeadings(markdown UL usage, -1)} else {},
            {markdown rest},
            apply(citations, markdown)),
        join(apply(footer, markdown), if page === null then {} else {
            MdParagraph {"Original documentation: ", MdLink {onlinePage(page#0, page#1), "Macaulay2 website"}, "."}}))
)

-- The function of a node: the function of a method node, or the node's own object.
nodeFunctionName := primary -> format makeDocumentTag(if isMethodKey primary.Key then first primary.Key else primary.Key)

-- For a method of an alias of the function its node documents, which alias:
-- "A method of addVertices, an alias of addVertex; "; nothing otherwise.
aliasNote := (tag, primary) -> (
    functionName := format makeDocumentTag first tag.Key;
    if functionName === nodeFunctionName primary then {}
    else {"A method of ", MdCode functionName, ", an alias of ", MdCode nodeFunctionName primary, "; "}
)

-- The chapter of a method on a page (package, page name), and the footer it adds
-- to the page: its node, when that is shown as the chapter; otherwise its heading
-- and where it is documented, if it is.
methodChapter := (tag, page) -> (
    heading := MdHeading(2, MdCode format tag);
    if documentationPage tag === null then (
        source := methodSource tag.Key;
        return (MdDocument prepend(heading, shiftHeadings(detailsSection join(
                {("Documentation", {"none"})},
                if source =!= null then {("Defined at", {MdCode sourceText source})} else {}), 1)), {}));
    primary := primaryTag tag;
    if format primary === format tag and isChapterNode primary then (
        (node, footer) := bookNode primary;
        (shiftHeadings(node, 1), if #footer == 0 then {} else prepend(MdParagraph MdStrong format tag, footer)))
    else (
        note := aliasNote(tag, primary);
        (MdDocument {heading, MdParagraph join(
                if #note == 0 then {"Documented "} else append(note, "documented "),
                if take(bookLocation primary, 2) === page then {"above."}
                else {"with ", MdDocLink {primary, format primary}, "."})}, {}))
)

-- Where a key is defined, when that is known: a symbol's definition.
keySource := method(Dispatch => Thing)
keySource Thing := key -> null
keySource Symbol := locate

-- The top of a page made for an exported symbol without documentation: the
-- details known about it.
missingIntroduction := tag -> (
    source := keySource tag.Key;
    ancestry := ancestorsLine keyObject tag.Key;
    (MdDocument join({objectHeading(1, tag.Key, format tag)}, ancestry, detailsSection join(
            if #ancestry == 0 then {("Class", {MdCode toString class keyObject tag.Key})} else {},
            packageFacts(tag.Key, documentingPackage tag.Package),
            {("Documentation", {"none"})},
            if source =!= null then {("Defined at", {MdCode sourceText source})} else {})), {})
)

-- The top of a page made in a package for the methods it installs on a function
-- without a page there: the function, and where it is documented, if anywhere.
functionPageIntroduction := (functionTag, pkgname) -> (
    title := format functionTag;
    origin := documentationPage functionTag;
    (MdDocument join({objectHeading(1, functionTag.Key, title)}, detailsSection join(
            {("Class", {MdCode toString class keyObject functionTag.Key})},
            packageFacts(functionTag.Key, pkgname),
            {("Documentation", if origin === null then {"none"} else {MdDocLink {functionTag, title}, " in ", origin#0})}),
        {MdParagraph {pkgname, " installs the methods below."}}), {})
)

-- The section of the table of contents listing a page of an exported object, as
-- the exports of a package's top page group them; null for an overview. A key is
-- one key.
exportSection := method(Dispatch => Thing)
exportSection Thing := key -> "Other things"
exportSection Type := key -> "Types"
exportSection Function :=
    exportSection Command := key -> "Functions and commands"
-- a symbol by its value; a symbol without a value is listed as itself
exportSection Symbol := key -> if value key === key then "Symbols" else exportSection value key
-- the raw documentation of an installed package keeps a symbol's key as its name
exportSection String := key -> if isGlobalSymbol key then exportSection getGlobalSymbol key

-- The sections of the table of contents, in order; "Methods" lists the pages made
-- for functions documented elsewhere.
bookSections = {"Types", "Functions and commands", "Methods", "Symbols", "Other things"}

-- A section of the table of contents is a page of its own, listing its pages and
-- linking to the package's main page: an entry of the table of contents links to
-- a page, and each page appears in it once.
sectionPageName := section -> replace(" ", "-", toLower section)
sectionDocument := (pkgname, section, entries) -> MdDocument {
    MdHeading(1, section),
    MdParagraph {"Part of the exports of ", MdLink {"index.md", pkgname}, "."},
    MdList apply(entries, (name, title) -> {MdLink {name | ".md", title}})}

-- The methods of an exported object; a method key is one key.
exportedMethods := method(Dispatch => Thing)
exportedMethods Thing := x -> {}
exportedMethods Type :=
exportedMethods Function :=
exportedMethods Keyword :=
exportedMethods ScriptedFunctor := x -> toList methods x

-- The packages whose code a package documents: itself, and Core for Macaulay2Doc.
sourcePackages := pkg -> unique prepend(pkg, select(loadedPackages, source ->
    documentingPackage source#"pkgname" === documentingPackage pkg#"pkgname"))

-- The methods a package shows, as tags: the methods it documents, and the
-- methods of the exported objects of its code it installs; a method listed once.
packageMethods := pkg -> (
    pkgname := documentingPackage pkg#"pkgname";
    documented := select(apply(packageRawDocumentation pkg, rawdoc -> rawdoc.DocumentTag),
        tag -> isMethodKey tag.Key);
    exported := flatten apply(sourcePackages pkg, source -> values source.Dictionary);
    installed := select(apply(unique flatten apply(exported, sym ->
            exportedMethods value sym), makeDocumentTag),
        tag -> isMethodKey tag.Key and methodPackage tag === pkgname);
    byFormat := new MutableHashTable;
    scan(join(documented, installed), tag -> if not byFormat#?(format tag) then byFormat#(format tag) = tag);
    values byFormat
)

-- A page of the book layout: its title, the section of the table of contents
-- listing it, a function making its top and the footer that adds, and the
-- methods shown as its chapters.
protect PageTitle
protect PageSection
protect PageTop
protect PageChapters

bookPage := (title, section, top, chapters) -> new HashTable from {
    symbol PageTitle => title,
    symbol PageSection => section,
    symbol PageTop => top,
    symbol PageChapters => last \ sort apply(chapters, tag -> (format tag, tag))
}

-- The pages of a package in the book layout, page name => page: a page for each
-- node other than a method's, for each exported symbol without documentation,
-- and for each function documented elsewhere, or nowhere, it shows methods of.
packageBookPages = pkg -> (
    pkgname := documentingPackage pkg#"pkgname";
    nodeTags := select(packageTags pkg, tag -> not isChapterNode tag);
    nodePages := hashTable apply(nodeTags, tag -> (documentationPage tag)#1 => tag);
    -- symbols of the same name, from several dictionaries, share their page
    missingTags := select(flatten apply(sourcePackages pkg, packageSymbolTags), tag ->
            isMissingDoc tag and not isUndocumented tag);
    missingPages := hashTable(first, apply(missingTags, tag -> toFilename format tag => tag));
    if #nodePages + #missingPages != #(set keys nodePages + set keys missingPages) or
        #nodePages != #nodeTags then
        error("M2Book: page names collide in ", pkgname);
    chapters := partition(tag -> (methodPage tag)#1,
        select(packageMethods pkg, tag -> (methodPage tag)#0 === pkgname));
    chaptersOf := page -> if chapters#?page then chapters#page else {};
    functionPages := select(keys chapters, page -> not nodePages#?page and
            not missingPages#?page);
    hashTable join(
        apply(pairs nodePages, (page, tag) -> page => bookPage(format tag, exportSection tag.Key,
            () -> bookNode tag, chaptersOf page)),
        apply(pairs missingPages, (page, tag) -> page => bookPage(format tag, exportSection tag.Key,
            () -> missingIntroduction tag, chaptersOf page)),
        apply(functionPages, page -> (
            functionTag := makeDocumentTag first (first chapters#page).Key;
            page => bookPage(format functionTag, "Methods", () ->
                    functionPageIntroduction(functionTag, pkgname), chaptersOf page)
        ))
    )
)

-- A page of the book layout, named in a package, as a document: its top, the
-- chapter "Installations" holding a section for each of its methods, then below
-- a rule the footers of its top and of its methods.
bookPageDocument = (pkgname, name, page) -> (
    (top, topFooter) := page.PageTop();
    chapters := apply(page.PageChapters, tag -> methodChapter(tag, (pkgname, name)));
    footers := join(topFooter, flatten apply(chapters, last));
    MdDocument join({top},
        if #chapters > 0 then prepend(MdHeading(2, "Installations"), apply(chapters, chapter -> shiftHeadings(first chapter, 1))) else {},
        if #footers > 0 then prepend(MdRule(), footers) else {})
)

mdBookPage = method(Dispatch => Thing)
mdBookPage Thing := MdDocument => key -> (
    location := bookLocation makeDocumentTag key;
    if location === null then
        error("M2Book: no page shows ", toString key);
    pages := packageBookPages needsPackage location#0;
    if not pages#?(location#1) then
        error("M2Book: no page shows ", toString key);
    bookPageDocument(location#0, location#1, pages#(location#1))
)

-----------------------------------------------------------------------------
-- The pages of a package
-----------------------------------------------------------------------------

-- The pages of packageBookPages; a node shown as a chapter is listed where its
-- page is.
bookLayout := (pkg, tags) -> (
    pkgname := pkg#"pkgname";
    pages := packageBookPages pkg;
    pageOf := tag -> (
        location := bookLocation tag;
        if location =!= null and location#0 === pkgname and pages#?(location#1) then
            (location#1, pages#(location#1).PageTitle));
    nodePages := set apply(select(tags, tag -> pageOf tag =!= null), tag -> (pageOf tag)#0);
    sectionEntries := select(apply(bookSections, section -> (section,
            apply(select(sort keys pages, name -> pages#name.PageSection === section), name -> (name, pages#name.PageTitle)))),
        (section, entries) -> #entries > 0);
    sectionPage := section -> if section =!= null then (sectionPageName section, section);
    new HashTable from {
        Documents => merge(
            applyPairs(pages, (name, page) -> (name, () -> bookPageDocument(pkgname, name, page))),
            hashTable apply(sectionEntries, (section, entries) -> sectionPageName section =>
                () -> sectionDocument(pkgname, section, entries)),
            (page, section) -> error("M2Book: a page is named like a section in ", pkgname)),
        PageOf => pageOf,
        OutlineOrder => join(select(tags, tag -> not isChapterNode tag), select(tags, isChapterNode)),
        ExtraPages => apply(select(sort keys pages, name -> not nodePages#?name), name -> (name, pages#name.PageTitle)),
        Sections => apply(sectionEntries, (section, entries) -> sectionPage section),
        SectionOf => page -> sectionPage pages#(page#0).PageSection,
        ResolveLink => resolveBookLink}
)

writeMdBook = method(Options => packageDirectoryOptions)
writeMdBook (String, String) := String => opts -> (name, dir) -> writeMdBook(needsPackage name, dir, opts)
writeMdBook (Package, String) := String => opts -> (pkg, dir) -> writePackageDirectory(pkg, dir, opts, bookLayout)
