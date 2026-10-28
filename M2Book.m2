-- -*- coding: utf-8 -*-
newPackage(
    "M2Book",
    Version => "0.1.0",
    Date => "October 28, 2026",
    Headline => "Alternative book presentation of Macaulay2 documentation",
    Authors => {{
        Name => "Alexander Golys",
        Email => "alexandergolys@gmail.com"
    }},
    HomePage => "https://github.com/AlexanderGolys/M2Book",
    Keywords => {"Documentation"},
    PackageExports => {"MarkdownDocs"},
    AuxiliaryFiles => true,
    DebuggingMode => false
)

export {
    "m2BookPage", "writeM2Book", "viewM2Book",
    "writeCuratedM2Book", "viewCuratedM2Book",
    "installBookTools",
    -- runtime facts for reference pages and the LSP index
    "buildReference", "writeReferenceJSON", "standardPackageNames",
    "packageReferenceNames"
}

-- the book layout: a page for every object, its methods as its sections
load "./M2Book/bookLayout.m2"
load "./M2Book/editions.m2"
-- the books built, served and opened in the browser
load "./M2Book/viewer.m2"

-- Runtime metadata shared by reference documentation and language tools.
load "./M2Book/reference.m2"

beginDocumentation()

doc ///
Node
  Key
    M2Book
  Headline
    Alternative book presentation of Macaulay2 documentation
  Description
    Text
      M2Book generates an alternative book presentation of local Macaulay2
      documentation, reorganizing chapters and links around objects and their
      methods. The current implementation uses mdBook to render and serve this
      book in the browser. Both M2Book and MarkdownDocs require the mdbook
      executable.

      The book is the central feature. At this stage the package generates the
      alternative chapter layout and enriches the baseline with runtime facts.
      The generated Markdown also provides a starting point for later manual
      rewrites and editorial development of the book.

      @TO "MarkdownDocs"@ provides essentially the original documentation
      browsing experience through a different rendering engine. It preserves
      the original content and organization in Markdown and mdBook, improves
      typography and graphics, and offers browser access to local documentation
      similar to Core's @TO viewHelp@. Keeping this faithful edition separate
      allows M2Book to develop its own presentation and editorial choices.

      Generation supplies a starting point for the book. Further development
      can involve extensive manual rewrites as well as structural changes
      implemented by the package. For example, the book groups a method
      function's installations into sections of its reference page and changes
      links to those installations into links to the corresponding sections.

      Runtime metadata is a foundation for this enrichment. Method signatures,
      options, type relationships, mutability and source definitions can be
      available through runtime inspection even when the documentation omits
      them. @TO buildReference@ and @TO writeReferenceJSON@ collect these facts
      to support richer documentation in the book. The extracted metadata can
      also be exported for use by other tools.

      The book layout has a page for each object. Installed methods, documented
      or not, are sections of the function's page; exported symbols without
      documentation have pages of their own. @TO m2BookPage@ shows an object's
      page, @TO writeM2Book@ writes a package's pages and table of contents, and
      @TO viewM2Book@ generates and serves the baseline book in the browser.
      Running these generation commands again replaces their generated pages;
      manual rewrites should be preserved through targeted updates. Edited pages
      are kept in the repository's {\tt curated} directory, and
      @TO writeCuratedM2Book@ and @TO viewCuratedM2Book@ build the curated
      edition by overlaying them on a fresh baseline.
    Example
      needsPackage "Graphs";
      class m2BookPage (degree, Digraph, Thing)
  Subnodes
    viewM2Book
    m2BookPage
    writeM2Book
    writeCuratedM2Book
    viewCuratedM2Book
    installBookTools
    buildReference
    writeReferenceJSON
    standardPackageNames
    packageReferenceNames
Node
  Key
    installBookTools
  Headline
    install and check the book renderer, preprocessors and syntax parsers
  Usage
    installBookTools()
  Outputs
    :Boolean
      true when setup succeeds, or false when installation is declined
  Description
    Text
      When book tools are missing, this asks for confirmation before running
      the bundled Bash installer. It installs the missing mdbook, mdbook-tsitter
      and mdbook-katex executables through Cargo. If Cargo is missing, the
      confirmation explicitly includes installing Rust and Cargo through the
      official rustup installer with a minimal stable profile. Existing tools
      are retained. Shell startup files are left unchanged.

      A small temporary book checks math rendering and syntax highlighting and
      lets mdbook-tsitter fetch and compile the Macaulay2 and BibTeX parsers.
      Fetching grammars requires network access, Git and a C compiler.

      Tools are installed below the application directory in M2Book/tools, or
      the directory given by the environment variable M2BOOK_TOOLS_ROOT. M2Book
      makes that directory and the Cargo bin directory available to its child
      processes immediately and on subsequent sessions. Rustup uses its normal
      directories, respecting CARGO_HOME and RUSTUP_HOME when set.

      @TO viewM2Book@ calls this when dependencies are missing, before generating
      the book. It cancels opening the book if installation is declined or fails.
      Calling this function explicitly also checks an existing tool installation.
  SeeAlso
    viewM2Book
Node
  Key
    m2BookPage
    (m2BookPage, Thing)
  Headline
    the page of an object in the book layout
  Usage
    m2BookPage key
  Inputs
    key:
      a documentation key, such as a function, a method key, or a string
  Outputs
    :MdDocument
      the page showing the key, in the layout of @TO writeM2Book@
  Description
    Text
      A page shows an object: below its title, its headline and a section
      {\tt Details} listing its class, or the chain of ancestors of a type, the
      package it belongs to when another package documents it, its aliases, and
      its inputs and outputs; then its usage and the description of its
      documentation node, with the citation at the end.

      The methods installed on a function are not pages of their own but sections
      of the chapter {\tt Installations} of the function's page, in order of their
      names, every method the package shows, documented or not. A section is
      headed by the method, as in @TT "degree(Digraph,Thing)"@, and holds its
      documentation node, when that documents the method alone, a link to the
      node documenting it otherwise, or else where it is defined. When the
      function is documented in another package, or nowhere, the page is made in
      the method's package, named after the function, linking to its
      documentation. An exported symbol without documentation also has a page,
      with the details known about it.

      Below a rule at the bottom of the page are the source locations of its
      documentation and a link to the original documentation on the Macaulay2
      website.

      For a method key the page is the page holding its section; for any other
      key it is the key's own page. @TO writeM2Book@ links a method to its page,
      followed by the identifier mdBook gives the heading of its section.
    Example
      m2BookPage "VerticalSpace"
  SeeAlso
    mdDocsPage
    writeM2Book
Node
  Key
    writeM2Book
    (writeM2Book, String, String)
    (writeM2Book, Package, String)
    [writeM2Book, LinkedPackages]
    [writeM2Book, LinkStyle]
  Headline
    write a package's documentation as a book of Markdown pages
  Usage
    writeM2Book(name, dir)
    writeM2Book(pkg, dir)
  Inputs
    name:String
      the name of a package, loaded if needed
    pkg:Package
    dir:String
      the directory the package directory is written in
    LinkedPackages => List
      as for @TO writeMdDocs@
    LinkStyle => String
      as for @TO writeMdDocs@
  Outputs
    :String
      the package directory, {\tt dir/name}
  Consequences
    Item
      the package directory is replaced by the pages of the package, a table of
      contents and the images the pages show, as described in
      @TO "MarkdownDocs :: Markdown documentation layout"@
  Description
    Text
      This writes the pages of @TO m2BookPage@: a page for every node other than
      an installed method, which is a section of its function's page, a page for
      each exported symbol without documentation, and a page for each function
      documented elsewhere that the package installs methods for. Links to such a
      method point at its section's heading, as in
      {\tt _degree.md#degreedigraphthing}, or {\tt [[Graphs/_degree#degree(Digraph,Thing)]]}
      as a wikilink.

      The table of contents lists the pages no menu lists under the sections of the
      exports, each a page of its own linking back to the main page: types,
      functions and commands, the pages made for methods, symbols, and other things.
      @TO writeBookFiles@ makes the directory an mdBook source.
    CannedExample
      i1 : writeM2Book("Graphs", "book", LinkedPackages => {"Macaulay2Doc"})

      o1 = book/Graphs
  SeeAlso
    writeMdDocs
    writeBookFiles
    viewM2Book
Node
  Key
    viewM2Book
    (viewM2Book, String)
    (viewM2Book, Package)
  Headline
    show a package's documentation as a book in the browser
  Usage
    viewM2Book name
    viewM2Book pkg
  Inputs
    name:String
      the name of a package, loaded if needed
    pkg:Package
  Outputs
    :String
      the address the book is served at
  Consequences
    Item
      the package directory is written by @TO writeM2Book@ below the application
      directory, in {\tt M2Book/markdown}, and made an mdBook source by
      @TO writeBookFiles@
    Item
      {\tt mdbook serve} serves the book in the background, and the browser opens it,
      as @TO viewHelp@ opens the HTML documentation
  Description
    Text
      This is @TO mdDocs@ for the book layout: the server keeps serving the book
      until Macaulay2 exits and rebuilds it when its directory is written again,
      each book on its own port. Its output is written to
      {\tt M2Book/<package>-<port>.log}, and the book is titled
      {\tt <package> — Generated}.
    CannedExample
      i1 : viewM2Book "Graphs"

      o1 = http://127.0.0.1:3000/
  SeeAlso
    writeM2Book
    viewCuratedM2Book
    mdDocs
Node
  Key
    writeCuratedM2Book
    (writeCuratedM2Book, String, String)
    (writeCuratedM2Book, String, String, String)
    [writeCuratedM2Book, LinkedPackages]
    [writeCuratedM2Book, LinkStyle]
  Headline
    write the curated edition of a package's book
  Usage
    writeCuratedM2Book(name, dir)
    writeCuratedM2Book(name, dir, repository)
  Inputs
    name:String
      the name of a package, loaded if needed
    dir:String
      the directory the package directory is written in, outside {\tt curated}
    repository:String
      the M2Book repository holding {\tt M2Book.m2} and {\tt curated}; by
      default, the directory M2Book was loaded from
    LinkedPackages => List
      as for @TO writeM2Book@
    LinkStyle => String
      as for @TO writeM2Book@
  Outputs
    :String
      the package directory, {\tt dir/name}, an mdBook source
  Consequences
    Item
      the package directory is replaced by the baseline of @TO writeM2Book@, made
      an mdBook source titled {\tt <name> — Curated}, and the files of
      {\tt curated/<name>} in the repository are copied over it
  Description
    Text
      The repository keeps only edited pages and their assets, at the same paths
      as their generated counterparts. Every other page comes from the current
      renderer, so improvements to the layout reach unchanged pages, while an
      edited page replaces its generated counterpart as a whole. The sources in
      {\tt curated} are never written to.

      An installed M2Book does not carry the repository, so pass it explicitly.
    CannedExample
      i1 : writeCuratedM2Book("Graphs", "book/curated", "/path/to/M2Book")

      o1 = /path/to/book/curated/Graphs
  SeeAlso
    viewCuratedM2Book
    writeM2Book
Node
  Key
    viewCuratedM2Book
    (viewCuratedM2Book, String)
    (viewCuratedM2Book, String, String)
  Headline
    show the curated edition of a package's book in the browser
  Usage
    viewCuratedM2Book name
    viewCuratedM2Book(name, repository)
  Inputs
    name:String
      the name of a package, loaded if needed
    repository:String
      the M2Book repository holding {\tt curated}, as for @TO writeCuratedM2Book@
  Outputs
    :String
      the address the book is served at
  Consequences
    Item
      the curated edition is written by @TO writeCuratedM2Book@ below the
      application directory, in {\tt M2Book/curated}, and served as by
      @TO viewM2Book@
  Description
    Text
      The generated and curated editions are served on separate ports, so both
      can stay open side by side for comparison.
    CannedExample
      i1 : viewCuratedM2Book "Graphs"

      o1 = http://127.0.0.1:3001/
  SeeAlso
    writeCuratedM2Book
    viewM2Book
Node
  Key
    buildReference
  Headline
    collect reference records from the running session
  Usage
    buildReference(names, packages)
  Inputs
    names:List
      of strings, the names to extract, or an empty list for every eligible name
    packages:List
      of strings, the packages to load and extract, or @TO null@ for everything
      visible in the session
  Outputs
    :List
      of reference records, one for each name, keyed by private schema symbols
  Description
    Text
      A reference record joins what the documentation says about a name with
      what the running session knows about its value. The documentation side
      holds the headline, description, examples and the node that documents it.
      The runtime side holds facts often missing from the prose: the class of
      the value, its aliases, the methods installed on a function together with
      their signatures, options and typical values, the ancestors of a type,
      whether the symbol can be reassigned, and where its value is defined, with
      the source lines of that definition.

      The packages are loaded first, so their dictionaries and documentation are
      available. Facts that cannot be determined are recorded as unknown rather than
      guessed.
    Example
      records = buildReference({"allowableThreads", "ZZ"}, {"Core"});
      #records
      class first records
    Text
      The records are intended for further processing in Macaulay2. For a stable
      representation with string field names, use @TO writeReferenceJSON@.
  SeeAlso
    writeReferenceJSON
    packageReferenceNames
Node
  Key
    writeReferenceJSON
  Headline
    write runtime reference records as JSON Lines
  Usage
    writeReferenceJSON(filename, names, packages)
  Inputs
    filename:String
      the destination file, replaced if it exists
    names:List
      of strings, the names to extract, or an empty list for every eligible name
    packages:List
      of strings, the packages to load and extract, or @TO null@ for everything
      visible in the session
  Outputs
    :ZZ
      the number of records written
  Consequences
    Item
      the file holds one JSON object per line, one for each record of
      @TO buildReference@
  Description
    Text
      Each line is a complete record with string field names, readable without
      Macaulay2. Several packages are extracted one at a time, and progress and
      timing are reported on @TO stderr@. When the environment variable
      M2BOOK_CHECKPOINT_DIR is set and the list of names is empty, each package
      is also saved there as a checkpoint when its extraction completes; the
      extraction scripts resume an interrupted run from these checkpoints.
    Example
      needsPackage "JSON";
      filename = temporaryFileName();
      writeReferenceJSON(filename, {"ZZ", "allowableThreads"}, {"Core"})
      records = apply(lines get filename, fromJSON);
      apply(records, record -> (record#"name", record#"kind", record#"class"))
    Text
      The field named mutable is @TO isMutable@ on the exported symbol: whether
      the symbol can be reassigned. The field named protected is its inverse.
      Assigning {\tt allowableThreads = 7} is allowed, while {\tt ZZ = 7} is
      not. These fields describe the binding, independently of whether the
      contents of its value can be modified. A failed query is represented by
      null.
    Example
      apply(records, record -> (record#"name", record#"mutable", record#"protected"))
    Text
      Source locations give the file of the definition with its start and stop
      rows and columns: rows count from one and columns from zero, with an
      exclusive stop column, as @TO locate@ reports them. The field named source
      holds the source lines of that span when the file is readable. A function
      built with options, @TO memoize@ or @TO cacheValue@ is located at the
      function it wraps rather than at the wrapper in Core. Both fields are null
      for compiled builtins without a recorded definition, including the methods
      that only declare the typical value of a compiled function.
    Example
      sort keys first records
      removeFile filename
  SeeAlso
    buildReference
    standardPackageNames
Node
  Key
    standardPackageNames
  Headline
    list the packages in the standard distribution
  Usage
    standardPackageNames()
  Outputs
    :List
      sorted package names including Core
  Description
    Text
      The packages distributed with Macaulay2 are those found in the directory of
      its own package sources, together with Core. This is the list a complete
      extraction passes to @TO writeReferenceJSON@. It does not include packages
      installed separately by the user.
    Example
      names = standardPackageNames();
      #names
      take(names, 5)
      isSubset({"Core", "Graphs", "SimpleDoc"}, names)
  SeeAlso
    writeReferenceJSON
    packageReferenceNames
Node
  Key
    packageReferenceNames
  Headline
    list the canonical reference names owned by a package
  Usage
    packageReferenceNames name
  Inputs
    name:String
      a package name, loaded if necessary
  Outputs
    :List
      sorted canonical names, with aliases of the same value kept together
  Description
    Text
      The names are those a package owns: the package itself, its exported
      symbols and the operators it defines. A value reachable under several
      names, such as a symbol and its qualified form, is listed once by its
      canonical name, so a list of names can be split into parts without
      separating the aliases of one value. Session output variables such as
      {\tt o1} are omitted.
    Example
      packageReferenceNames "FirstPackage"
    Text
      Passing a part of this list as the names of @TO writeReferenceJSON@
      extracts a large package, such as Core, in several smaller runs.
  SeeAlso
    standardPackageNames
    writeReferenceJSON
///

TEST ///
  -- the book layout: installed methods are sections of their function's page
  needsPackage "Graphs";
  dir := temporaryFileName();
  packageDir := writeM2Book("Graphs", dir, LinkedPackages => {"Macaulay2Doc"});
  page := name -> get(packageDir | "/" | name | ".md");
  files := set readDirectory packageDir;
  assert not files#?"_degree_lp__Digraph_cm__Thing_rp.md";
  assert not files#?"_is__Cyclic_lp__Digraph_rp.md";
  -- a method on a function documented in Graphs: a section of its page's installations
  assert match("\n## Installations\n\n### `isCyclic\\(Digraph\\)`\n", page "_is__Cyclic");
  assert not match("Ways to use", page "_is__Cyclic");
  -- every method, documented or not, has a section; an alias's method says so
  addVertex := page "_add__Vertex";
  assert match("\n### `addVertices\\(Digraph,List\\)`\n\nA method of `addVertices`, an alias of `addVertex`; documented above\\.\n", addVertex);
  assert match("\n### `addVertices\\(Graph,List\\)`\n\n#### Details\n\n- \\*\\*Documentation:\\*\\* none\n", addVertex);
  -- the details below the headline: class and aliases, inputs and outputs
  assert match("\\A# `addVertex`\n\n> \\[!NOTE\\]\n> [^\n]*\n\n## Details\n\n- \\*\\*Class:\\*\\* a \\[method function\\]", addVertex);
  assert match("\n- \\*\\*Aliases:\\*\\* `addVertices`\n- \\*\\*Inputs:\\*\\*\n", addVertex);
  assert not match("For the programmer", addVertex);
  -- the footer at the bottom of the page, after the installations
  assert match("\n\\*\\*\\*\n\nThe source of this document is in [^\n]*\n\nOriginal documentation: [^\n]*\n\\z", addVertex);
  -- a method on a function documented in Macaulay2Doc: a page made for it in Graphs
  degreePage := page "_degree";
  assert match("\\A# `degree`\n\n## Details\n\n- \\*\\*Class:\\*\\* `MethodFunction`\n- \\*\\*Package:\\*\\* `Core`\n- \\*\\*Documentation:\\*\\* \\[`degree`\\]\\(\\.\\./Macaulay2Doc/_degree\\.md\\) in Macaulay2Doc\n", degreePage);
  assert match("\n### `degree\\(Digraph,Thing\\)`\n", degreePage);
  -- a type shows its ancestors below its title
  assert match("\\A# `Graph`\n\n<div align=\"center\">\n\n\\[`Graph`\\]\\(___Graph\\.md\\)&ensp;←&ensp;\\[`Digraph`\\]\\(___Digraph\\.md\\)&ensp;←&ensp;\\[`HashTable`\\]", page "___Graph");
  -- an exported symbol without documentation has a page
  assert match("\\A# `discoveryTime`\n\n## Details\n\n- \\*\\*Class:\\*\\* `Symbol`\n", page "_discovery__Time");
  -- links to a method point at its section's heading
  assert match("\\(_degree\\.md#degreedigraphthing\\)", page "___Digraph");
  -- the table of contents: a page for each section of the exports
  contents := get(packageDir | "/contents.md");
  assert match("\n- \\[Types\\]\\(types\\.md\\)\n  - \\[Digraph\\]\\(___Digraph\\.md\\)\n", contents);
  assert match("\n- \\[Methods\\]\\(methods\\.md\\)\n(  - [^\n]*\n)*  - \\[degree\\]\\(_degree\\.md\\)\n", contents);
  assert match("\\A# Types\n\nPart of the exports of \\[Graphs\\]\\(index\\.md\\)\\.\n", page "types");
  -- the page of a method key is the page holding its section
  assert match("\\A# `degree`\n", toString m2BookPage (degree, Digraph, Thing))
///

TEST ///
  needsPackage "JSON";
  filename := temporaryFileName();
  assert(writeReferenceJSON(filename, {"ZZ", "Type", "allowableThreads", "pi", "path", "degree"}, {"Core"}) == 6);
  records := hashTable apply(lines get filename, line -> (
      record := fromJSON line;
      record#"name" => record));
  assert(records#"ZZ"#"protected" === true);
  assert(records#"ZZ"#"mutable" === false);
  assert(records#"Type"#"protected" === true);
  assert(records#"Type"#"mutable" === false);
  assert(records#"allowableThreads"#"protected" === false);
  assert(records#"allowableThreads"#"mutable" === true);
  assert(records#"pi"#"protected" === true);
  assert(records#"pi"#"mutable" === false);
  assert(records#"path"#"protected" === not isMutable symbol path);
  assert(records#"path"#"mutable" === isMutable symbol path);
  assert(#(records#"degree"#"methods") > 0);
  removeFile filename;
///
