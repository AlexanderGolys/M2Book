-- -*- coding: utf-8 -*-
newPackage(
    "M2Book",
    Version => "0.1",
    Date => "October 20, 2026",
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

-- Keep this package's book commands distinct from similarly named commands
-- exported by MarkdownDocs.
dictionaryPath = prepend(currentPackage#"private dictionary",
    delete(currentPackage#"private dictionary", dictionaryPath))

export {
    "mdBookPage", "writeMdBook", "mdBook",
    "installBookTools",
    -- runtime facts for reference pages and the LSP index
    "buildReference", "writeReferenceJSON", "standardPackageNames",
    "packageReferenceNames"
}

-- the book layout: a page for every object, its methods as its sections
load "./M2Book/bookLayout.m2"
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
      documentation have pages of their own. @TO mdBookPage@ shows an object's
      page, @TO writeMdBook@ writes a package's pages and table of contents, and
      @TO mdBook@ generates and serves the baseline book in the browser.
      Running these generation commands again replaces their generated pages;
      manual rewrites should be preserved through targeted updates.
    Example
      needsPackage "Graphs";
      class mdBookPage (degree, Digraph, Thing)
  Subnodes
    mdBook
    mdBookPage
    writeMdBook
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

      @TO mdBook@ calls this when dependencies are missing, before generating
      the book. It cancels opening the book if installation is declined or fails.
      Calling this function explicitly also checks an existing tool installation.
  SeeAlso
    mdBook
Node
  Key
    mdBookPage
    (mdBookPage, Thing)
  Headline
    the page of an object in the book layout
  Usage
    mdBookPage key
  Inputs
    key:
      a documentation key, such as a function, a method key, or a string
  Outputs
    :MdDocument
      the page showing the key, in the layout of @TO writeMdBook@
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
      key it is the key's own page. @TO writeMdBook@ links a method to its page,
      followed by the identifier mdBook gives the heading of its section.
    Example
      mdBookPage "VerticalSpace"
  SeeAlso
    mdDocsPage
    writeMdBook
Node
  Key
    writeMdBook
    (writeMdBook, String, String)
    (writeMdBook, Package, String)
    [writeMdBook, LinkedPackages]
    [writeMdBook, LinkStyle]
  Headline
    write a package's documentation as a book of Markdown pages
  Usage
    writeMdBook(name, dir)
    writeMdBook(pkg, dir)
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
      This writes the pages of @TO mdBookPage@: a page for every node other than
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
      i1 : writeMdBook("Graphs", "book", LinkedPackages => {"Macaulay2Doc"})

      o1 = book/Graphs
  SeeAlso
    writeMdDocs
    writeBookFiles
    mdBook
Node
  Key
    mdBook
    (mdBook, String)
    (mdBook, Package)
  Headline
    show a package's documentation as a book in the browser
  Usage
    mdBook name
    mdBook pkg
  Inputs
    name:String
      the name of a package, loaded if needed
    pkg:Package
  Outputs
    :String
      the address the book is served at
  Consequences
    Item
      the package directory is written by @TO writeMdBook@ below the application
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
      {\tt M2Book/<package>.log}.
    CannedExample
      i1 : mdBook "Graphs"

      o1 = http://127.0.0.1:3000/
  SeeAlso
    writeMdBook
    mdDocs
Node
  Key
    buildReference
  Headline
    collect reference records from the running session
  Usage
    buildReference(names, packages)
  Inputs
    names:List
      symbol names to extract, or an empty list for every eligible symbol
    packages:List
      package names to load and extract; null selects the visible runtime
  Outputs
    :List
      reference records keyed by private schema symbols
  Description
    Text
      The records include documentation and runtime facts. For a stable JSON
      representation with string field names, use @TO writeReferenceJSON@.
Node
  Key
    writeReferenceJSON
  Headline
    write runtime reference records as JSON Lines
  Usage
    writeReferenceJSON(filename, names, packages)
  Inputs
    filename:String
      the destination file
    names:List
      symbol names to extract, or an empty list for all eligible symbols
    packages:List
      package names to load and extract; null selects the visible runtime
  Outputs
    :ZZ
      the number of records written
  Description
    Text
      Each line is a complete reference record. The field named protected is
      the negation of @TO isMutable@ on the symbol, while mutable is
      @TO isMutable@ on its value. A failed query is represented by null.
      Mutability of a type describes the type object itself, not its instances.
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
Node
  Key
    packageReferenceNames
  Headline
    list the canonical reference names owned by a package
  Usage
    packageReferenceNames(name)
  Inputs
    name:String
      a package name, loaded if necessary
  Outputs
    :List
      sorted canonical names, with aliases of the same value kept together
///

TEST ///
  -- the book layout: installed methods are sections of their function's page
  needsPackage "Graphs";
  dir := temporaryFileName();
  packageDir := writeMdBook("Graphs", dir, LinkedPackages => {"Macaulay2Doc"});
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
  assert match("\\A# `degree`\n", toString mdBookPage (degree, Digraph, Thing))
///

TEST ///
  needsPackage "JSON";
  filename := temporaryFileName();
  assert(writeReferenceJSON(filename, {"ZZ", "pi", "path", "degree"}, {"Core"}) == 4);
  records := hashTable apply(lines get filename, line -> (
      record := fromJSON line;
      record#"name" => record));
  assert(records#"ZZ"#"protected" === true);
  assert(records#"ZZ"#"mutable" === isMutable ZZ);
  assert(records#"pi"#"protected" === true);
  assert(records#"pi"#"mutable" === false);
  assert(records#"path"#"protected" === not isMutable symbol path);
  assert(records#"path"#"mutable" === isMutable path);
  assert(#(records#"degree"#"methods") > 0);
  removeFile filename;
///
