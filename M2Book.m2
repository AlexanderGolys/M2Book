-- -*- coding: utf-8 -*-
newPackage(
    "M2Book",
    Version => "0.1.0",
    Date => "October 28, 2026",
    Headline => "Alternative book presentation of Macaulay2 documentation",
    Authors => {{
        Name => "Alexander Golys",
        Email => "alexandergolys@gmail.com",
        HomePage => "https://spectralflux.dev"
    }},
    HomePage => "https://github.com/AlexanderGolys/M2Book",
    Keywords => {"Documentation"},
    PackageExports => {"MarkdownDocs"},
    AuxiliaryFiles => true,
    DebuggingMode => false
)

export {
    -- the book in the browser, as viewHelp shows the documentation
    "viewBook", "Edition",
    "bookPage", "generateBookBase", "installBookTools",
    -- facts about objects gathered from the running session
    "ObjectFacts", "objectFacts", "packageObjectFacts",
    -- the index the m2-ls language server reads
    "writeLSPIndex", "Names"
}

-- the book layout: a page for every object, its methods as its sections
load "./M2Book/bookLayout.m2"
load "./M2Book/editions.m2"
-- the books built, served and opened in the browser
load "./M2Book/viewer.m2"

-- Facts about objects from the running session, for the book and the m2-ls index.
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
      M2Book presents the Macaulay2 documentation as a book: a page for every
      object, with the methods installed on a function as sections of its page,
      documented or not. @TO viewBook@ opens it in the browser, as @TO viewHelp@
      opens the HTML documentation; the book is rendered and served by mdBook.

      The book has two editions. The generated edition is the baseline,
      written from the installed documentation by @TO generateBookBase@ and
      replaced whenever it is generated again. The curated edition is the book
      itself: edited pages, kept in the {\tt curated} directory of the package,
      replace their generated counterparts, while every other page follows the
      current baseline. @TO viewBook@ shows the curated edition unless told
      otherwise.

      @TO "MarkdownDocs"@ provides essentially the original documentation
      browsing experience through a different rendering engine. It preserves
      the original content and organization in Markdown and mdBook. Keeping
      this faithful edition separate allows M2Book to develop its own
      presentation and editorial choices.

      Much of what a reader needs is missing from the prose of the
      documentation but known to the running session: the methods installed on
      a function and their return types, options with their defaults, type
      relationships, whether a symbol can be reassigned, and where an object is
      defined. @TO objectFacts@ gathers these facts from the many tables
      holding them, and @TO writeLSPIndex@ writes them as the index the m2-ls
      language server reads.
    Example
      needsPackage "Graphs";
      class bookPage (degree, Digraph, Thing)
  Subnodes
    viewBook
    Edition
    bookPage
    generateBookBase
    installBookTools
    objectFacts
    ObjectFacts
    packageObjectFacts
    writeLSPIndex
Node
  Key
    viewBook
    (viewBook, Thing)
    (viewBook, String)
    (viewBook, DocumentTag)
  Headline
    view the book in the browser
  Usage
    viewBook
    viewBook key
  Inputs
    key:
      a documentation key, such as a function, a method key, a package name,
      or a string
  Outputs
    :String
      the address of the page
  Consequences
    Item
      the book of the package documenting the key is written below the
      application directory, in {\tt M2Book/curated} or {\tt M2Book/generated},
      the first time it is viewed in a session
    Item
      {\tt mdbook serve} serves the book in the background, each book on its own
      port, until Macaulay2 exits, and the browser opens the page
  Description
    Text
      This is @TO viewHelp@ for the book. Without a key it opens the book of
      Macaulay2Doc; with a key, the page showing it, scrolled to its section
      when the key is a method. A package name opens the front page of its book.
    CannedExample
      i1 : viewBook (degree, Digraph, Thing)

      o1 = http://127.0.0.1:3000/_degree.html#degreedigraphthing
    Text
      The option @TO Edition@ chooses the edition: the generated edition can be
      opened beside the curated one, to compare an edited page with the current
      baseline.
    CannedExample
      i2 : viewBook((degree, Digraph, Thing), Edition => "Generated")

      o2 = http://127.0.0.1:3001/_degree.html#degreedigraphthing
    Text
      Missing book tools are installed first, after confirmation, by
      @TO installBookTools@. The result of @TO about@ is a list of keys, so an
      entry of it is viewed with {\tt viewBook (about "...")#i}.
  SeeAlso
    bookPage
    generateBookBase
    viewHelp
Node
  Key
    Edition
  Headline
    the edition of the book to view
  Description
    Text
      An option of @TO viewBook@: {\tt "Curated"}, the default, views the book,
      and {\tt "Generated"} views its baseline, written by
      @TO generateBookBase@.
    CannedExample
      i1 : viewBook("Graphs", Edition => "Generated")

      o1 = http://127.0.0.1:3001/index.html
  SeeAlso
    viewBook
Node
  Key
    bookPage
    (bookPage, Thing)
  Headline
    the page of an object in the book
  Usage
    bookPage key
  Inputs
    key:
      a documentation key, such as a function, a method key, or a string
  Outputs
    :MdDocument
      the page showing the key, as in the generated edition
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
      website. For a method key the page is the page holding its section; for
      any other key it is the key's own page.
    Example
      bookPage "VerticalSpace"
  SeeAlso
    viewBook
    generateBookBase
Node
  Key
    generateBookBase
    (generateBookBase, String, String)
    (generateBookBase, Package, String)
    [generateBookBase, LinkedPackages]
    [generateBookBase, LinkStyle]
  Headline
    write the generated edition of a package's book
  Usage
    generateBookBase(name, dir)
    generateBookBase(pkg, dir)
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
      the package directory, {\tt dir/name}, an mdBook source
  Consequences
    Item
      the package directory is replaced by the pages of the package, a table of
      contents and the images the pages show, and made an mdBook source titled
      {\tt <name> — Generated}
  Description
    Text
      The generated edition is the baseline the book starts from: a page of
      @TO bookPage@ for every node other than an installed method, which is a
      section of its function's page, for each exported symbol without
      documentation, and for each function documented elsewhere that the
      package installs methods for. Links to such a method point at its
      section's heading, as in {\tt _degree.md#degreedigraphthing}, or
      {\tt [[Graphs/_degree#degree(Digraph,Thing)]]} as a wikilink.

      The table of contents lists the pages no menu lists under the sections of
      the exports, each a page of its own linking back to the main page: types,
      functions and commands, the pages made for methods, symbols, and other
      things.

      Generating again replaces the pages, so an edited page belongs in the
      {\tt curated} directory of the package, at the path of its generated
      counterpart, rather than in a generated directory.
    CannedExample
      i1 : generateBookBase("Graphs", "book", LinkedPackages => {"Macaulay2Doc"})

      o1 = book/Graphs
  SeeAlso
    viewBook
    writeMdDocs
    writeBookFiles
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

      @TO viewBook@ calls this when dependencies are missing, before writing
      the book. It cancels opening the book if installation is declined or fails.
      Calling this function explicitly also checks an existing tool installation.
  SeeAlso
    viewBook
Node
  Key
    ObjectFacts
  Headline
    the type of the facts about an object
  Description
    Text
      Facts about an object are a hash table with string keys: the fields of
      a record of the m2-ls index, with their documentation-derived fields too.
      It is shown as a summary of its main facts; every field is available by
      its key.
    Example
      facts = objectFacts "allowableThreads"
      facts#"mutable"
      #(keys facts)
    Text
      The runtime facts come from the session rather than the prose:
      {\tt class}, {\tt ancestors} and {\tt aliases}; {\tt protected} and
      {\tt mutable}, whether the symbol can be reassigned, which describe the
      binding rather than the contents of its value; {\tt methods}, each
      installation with its {\tt domain}, its {\tt typicalValue} and its source;
      {\tt options}, each with its {\tt default}, the class of that default
      ({\tt defaultType}) and the type its documentation names
      ({\tt valueType}); and {\tt option_passing}, how a callable takes options:
      the keys of its option table, any names, those of the installation a call
      reaches, or none. {\tt source_location} and {\tt source} give the definition, with
      one-based rows and zero-based columns as @TO locate@ reports them. A fact
      that cannot be determined is null.
  SeeAlso
    objectFacts
    packageObjectFacts
Node
  Key
    objectFacts
    (objectFacts, Thing)
  Headline
    facts about an object gathered from the running session
  Usage
    objectFacts x
  Inputs
    x:
      a symbol, its name, or an object with a global name
  Outputs
    :ObjectFacts
  Description
    Text
      This joins what the documentation says about an object with what the
      running session knows about it, from the many tables holding those
      facts: the methods installed on a function and their return types, the
      options with their defaults and types, how options are passed, the
      ancestors of a type, whether a symbol can be reassigned, and where the
      object is defined.
    Example
      facts = objectFacts End;
      facts#"option_passing"
      first select(facts#"options", option -> option#"key" == "DegreeLimit")
      apply(take((objectFacts kernel)#"methods", 3), installation ->
          (installation#"domain", installation#"typicalValue"))
    Text
      Some fields relate an object to others extracted with it: the
      {\tt constructors} and {\tt common_operations} of a type, the functions
      accepting an option ({\tt option_key_for}). Extracted alone, an object has
      none to relate to, so these are null; @TO packageObjectFacts@ relates the
      objects of a package to each other.
  SeeAlso
    ObjectFacts
    packageObjectFacts
Node
  Key
    packageObjectFacts
    (packageObjectFacts, String)
    (packageObjectFacts, Package)
  Headline
    facts about every object of a package
  Usage
    packageObjectFacts name
    packageObjectFacts pkg
  Inputs
    name:String
      the name of a package, loaded if needed
    pkg:Package
  Outputs
    :List
      of @TO ObjectFacts@, one for each object the package owns
  Description
    Text
      The objects include the package itself, its exported symbols and the
      operators it defines; the fields relating objects, such as the
      constructors of a type, relate them to each other.
    Example
      apply(packageObjectFacts "FirstPackage", facts -> (facts#"name", facts#"kind"))
  SeeAlso
    objectFacts
Node
  Key
    writeLSPIndex
    (writeLSPIndex, String, List)
    [writeLSPIndex, Names]
    Names
  Headline
    write the index the m2-ls language server reads
  Usage
    writeLSPIndex(filename, packages)
  Inputs
    filename:String
      the index file, replaced if it exists
    packages:List
      of strings, the names of the packages to index
    Names => List
      of strings, the names to index, or empty for every name the packages own
  Outputs
    :ZZ
      the number of records written
  Description
    Text
      The index is a JSON Lines file: a meta record listing the packages a
      fresh session makes available, then one record for each object, with the
      facts of @TO objectFacts@ that a language server needs and the Markdown
      it shows on hover. The m2-ls language server downloads the index of the
      standard distribution from the releases of M2Book, so it rarely needs to
      be written by hand; this is how that index is made.
    CannedExample
      i1 : writeLSPIndex("m2-index.jsonl", {"Core"}, Names => {"ZZ", "degree"})

      o1 = 2
    Text
      The schema of a record is {\tt m2-index.schema.json} in the M2Book
      repository. Indexing the whole distribution is the work of the
      repository's scripts, which extract its packages in parallel.
  SeeAlso
    objectFacts
///

TEST ///
  -- the book layout: installed methods are sections of their function's page
  needsPackage "Graphs";
  dir := temporaryFileName();
  packageDir := generateBookBase("Graphs", dir, LinkedPackages => {"Macaulay2Doc"});
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
  assert match("\\A# `degree`\n", toString bookPage (degree, Digraph, Thing))
///

TEST ///
  facts := hashTable apply({"ZZ", "Type", "allowableThreads", "pi", "path", "degree"}, name ->
      name => objectFacts name);
  assert(facts#"ZZ"#"protected" === true);
  assert(facts#"ZZ"#"mutable" === false);
  assert(facts#"Type"#"protected" === true);
  assert(facts#"Type"#"mutable" === false);
  assert(facts#"allowableThreads"#"protected" === false);
  assert(facts#"allowableThreads"#"mutable" === true);
  assert(facts#"pi"#"protected" === true);
  assert(facts#"pi"#"mutable" === false);
  assert(facts#"path"#"protected" === not isMutable symbol path);
  assert(facts#"path"#"mutable" === isMutable symbol path);
  assert(#(facts#"degree"#"methods") > 0);
  -- extracted alone, the constructors of a type are unknown
  assert(facts#"ZZ"#"constructors" === null);
///

TEST ///
  needsPackage "JSON";
  filename := temporaryFileName();
  assert(writeLSPIndex(filename, {"Core"}, Names => {"ZZ", "degree"}) == 2);
  records := apply(lines get filename, fromJSON);
  assert((first records)#"kind" == "meta");
  assert member("Core", (first records)#"default_loaded");
  assert(set apply(drop(records, 1), record -> record#"name") == set {"ZZ", "degree"});
  removeFile filename;
///
