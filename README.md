# M2Book

M2Book presents the Macaulay2 documentation as a book, organized around objects
and their methods, and opens it in the browser the way `viewHelp` opens the HTML
documentation. The book is rendered and served by mdBook; M2Book offers to
install the book tools the first time they are needed.

The book has two editions:

- the **curated** edition is the book itself. Edited pages are kept in
  [`M2Book/curated/`](M2Book/curated/README.md) and replace their generated
  counterparts, while every other page follows the current baseline;
- the **generated** edition is the baseline written from the installed
  documentation. It is replaced whenever it is generated again, and it is what
  edited pages start from.

The split from [MarkdownDocs](https://github.com/AlexanderGolys/MarkdownDocs) is
intentional. MarkdownDocs offers essentially the original documentation-browsing
experience through a different rendering engine, preserving the original content
and organization. M2Book starts from that faithful edition for an alternative
presentation: rewritten explanations, expanded coverage, editorial preferences
and structural reorganization all belong here.

Much of what a reader needs is missing from the prose of the documentation but
known to the running session: the methods installed on a function and their
return types, options with their defaults and types, type relationships, whether
a symbol can be reassigned, and where an object is defined. M2Book gathers these
facts for the book, and writes them as the index the m2-ls language server reads.

## The book

```m2
needsPackage "M2Book"

viewBook                                  -- the book of Macaulay2Doc
viewBook "Graphs"                         -- the front page of the book of Graphs
viewBook (degree, Digraph, Thing)         -- the section of degree for digraphs
viewBook("Graphs", Edition => "Generated")   -- its generated baseline, side by side
```

Where the installed documentation has a page for each documentation node, the
book has a page for each object:

- the methods installed on a function, documented or not, are sections of the
  `Installations` chapter of its page;
- the methods a package installs on a function documented elsewhere are sections
  of a page made for that function in the package;
- an exported symbol without documentation has a page of its own;
- each page opens with its details (class or ancestors, aliases, package, inputs
  and outputs), and the table of contents groups the exports of the main page.

`viewBook` writes the book of a package below `~/.Macaulay2/M2Book/` the first
time it is viewed in a session and serves it with `mdbook serve` in the
background, each book on its own port, until Macaulay2 exits.

The generated edition can also be written anywhere, as a complete mdBook source,
and a single page inspected in Macaulay2:

```m2
-- book/Graphs: an mdBook source titled "Graphs — Generated"
generateBookBase("Graphs", "book", LinkedPackages => {"Macaulay2Doc"})

needsPackage "Graphs"
render bookPage (degree, Digraph, Thing)   -- Graphs' page for degree
```

A link to a method points at the heading of its section:
`_degree.md#degreedigraphthing`, or `[[Graphs/_degree#degree(Digraph,Thing)]]`
with `LinkStyle => "wikilink"`. The directory layout, links, `LinkedPackages` and
the mdBook configuration are those of MarkdownDocs.

## Facts about objects

```m2
objectFacts End                      -- a summary; every field by its name
(objectFacts End)#"option_passing"   -- "table"
packageObjectFacts "Graphs"          -- every object of a package
```

`objectFacts` joins what the documentation says about an object with what the
running session knows about it, from the many tables holding those facts. Its
fields are those of the LSP index records described below. Fields relating an
object to others extracted with it, such as the constructors of a type, are null
for a single object; `packageObjectFacts` relates the objects of a package to
each other.

## Installation

M2Book needs MarkdownDocs installed. Its viewer uses `mdbook`, `mdbook-tsitter`
for syntax highlighting, and `mdbook-katex` for mathematics. If tools are missing,
`viewBook` asks whether to install them before writing the book.

```m2
installPackage("MarkdownDocs", FileName => "/path/to/MarkdownDocs/MarkdownDocs.m2")
installPackage("M2Book", FileName => "/path/to/M2Book/M2Book.m2")
check "M2Book"
installBookTools()    -- optional: run setup and verification separately
```

Answer `y` or `yes` to approve installation. Enter, any other answer, or
end-of-input declines; opening the book is then cancelled. Setup uses
`cargo install --locked` for each missing tool and retains existing executables.
If Cargo is missing, the prompt explicitly includes installing Rust and Cargo
through the official rustup installer with the minimal stable profile. This does
not modify shell startup files.
Tools installed from M2 go under `~/.Macaulay2/M2Book/tools/bin` and are available
to M2Book immediately and in later sessions. Set `M2BOOK_TOOLS_ROOT` to use a
different installation prefix.

Setup builds a temporary test book to verify math and highlighting and let
tsitter fetch and compile the Macaulay2 and BibTeX parsers. Their first fetch
requires network access, Git and a C compiler; the parsers are cached for later
builds. Once installed, these tools and their generated C parsers run without a
Rust toolchain.

Rustup uses its normal installation directories (`~/.cargo` and `~/.rustup`),
respecting `CARGO_HOME` and `RUSTUP_HOME` when set. M2Book makes Cargo and the book
tools available to its child processes in the same session, so restarting M2 is
unnecessary.

For terminal use, `./scripts/install_book_tools.sh` invokes the same bundled
installer. It installs missing Rust/Cargo when necessary and uses the normal
Cargo installation prefix for book tools unless `M2BOOK_TOOLS_ROOT` is set. It prints
any PATH adjustment needed for the calling shell.

## The m2-ls index

m2-ls does not ship the index of the standard distribution. It downloads
`m2-index.jsonl` from the latest M2Book release, verifies it against the
`m2-index.jsonl.sha256` asset of the same release, and downloads again only when
a new release is published. The index is a JSON Lines file: a `meta` record
listing the packages a fresh session makes available (`default_loaded`), then one
record per object with its structural facts and hover Markdown. Its line schema
is [m2-index.schema.json](m2-index.schema.json).

`writeLSPIndex` writes such an index for chosen packages:

```m2
writeLSPIndex("m2-index.jsonl", {"Core"}, Names => {"ZZ", "degree"})
```

The index of the whole distribution is made by the scripts, which extract its
packages in parallel and keep the intermediate files:

```sh
# Facts, editable reference pages and the index; replaces reference/src.
./scripts/generate_reference.sh

# A smaller corpus, including the packages loaded by a fresh M2 session.
./scripts/generate_reference.sh packages=default,Text,JSON
```

Set `M2_BIN` to choose the Macaulay2 executable and `M2BOOK_JOBS` to control the
worker count for a full extraction (default: 4). Full extraction resumes completed
package checkpoints after interruption; `M2BOOK_CHECKPOINT_DIR` can override their
location. Keep a custom checkpoint directory exclusive to one extractor version.

The outputs are ignored by git:

- `m2-facts.jsonl`: runtime facts and documentation source information.
- `reference/src/`: reference Markdown pages, including missing documentation
  markers and runtime facts.
- `m2-reference.jsonl`: complete facts with editable documentation overlaid.
- `m2-index.jsonl`: the index m2-ls reads.

Machine facts remain separate from editable prose, so re-extraction preserves
documentation improvements. After editing the reference pages by hand, refresh the
runtime facts and assemble them with the existing prose, skipping rendering so the
edited pages are kept:

```sh
M2 --script scripts/extract_m2_facts.m2 m2-facts.jsonl packages=default
M2 --script scripts/assemble_jsonl.m2 reference/src m2-facts.jsonl m2-reference.jsonl m2-index.jsonl
```

Attach a regenerated index to a release with:

```sh
./scripts/publish_index.sh v0.1.0
```

m2-ls refuses a downloaded index that does not match its wire format, keeping
any previously cached copy, so publish an incompatible format change only
together with an m2-ls release that reads it.

### Fields

`mutable` reports whether an exported symbol can be reassigned (`isMutable` on
the symbol), and `protected` is its inverse. For example, `allowableThreads` is
mutable, whereas `ZZ` is protected: assigning `allowableThreads = 7` is allowed,
but assigning `ZZ = 7` is not. These fields describe the binding, independently
of whether the value's contents can be modified. Both are Boolean fields, or
`null` when the query fails.

Callables record how they take optional arguments. `option_passing` is `table`
when a function accepts exactly the keys of its option table, `open` when a
method function declared with `Options => false` accepts any names, `forwarded`
when one declared with `Options => true` passes them to the installation a call
reaches, and `absent` when it takes none. Each option lists its `default`,
the class of that default (`defaultType`) and the type its documentation gives
(`valueType`), which can be narrower than what the function accepts: the default
of `DegreeLimit` for `End` is `null`, while its documented type is `ZZ`. An
installation built with its own option table, as in `f(X) := {Labels => null} >>
o -> ...`, lists its options and `option_passing` itself. In the index both
types are `$Package$Name` references.

Object and method records retain `source_location` (absolute filename and
start/stop rows and columns from `locate`) and `source` (the source lines covering
that span when the file is readable). Missing locations or source text are
`null`, including compiled builtins without a recorded Macaulay2 definition.
Rows are one-based and columns are zero-based, using Macaulay2's native span
convention, with an exclusive stop column. When no implementation location is
recorded, extraction tries the symbol's declaration. Methods retain their own
implementation spans. A function built with options, `memoize` or `cacheValue`
is located at the function it wraps rather than at Core's wrapper, and methods
that only declare the typical value of a builtin have no location.

These facts appear in the reference pages and survive projection into the index.

## Development

Validate the book tools setup and the reference pipeline with
`M2 --script tests/all.m2`, or one part with `tests/bookTools.m2` or
`tests/referencePipeline.m2`. The tests and scripts load M2Book directly from
this checkout and use the installed MarkdownDocs. After installing M2Book,
`check "M2Book"` checks the book layout, the facts and the index.

## License

[GNU General Public License, version 3](LICENSE).
