# M2Book

M2Book generates an alternative book presentation of local Macaulay2
documentation, reorganizing chapters and links around objects and their methods.
It currently uses mdBook to render and serve that book in the browser, as
MarkdownDocs does for its faithful presentation. Both packages use the
`mdbook` executable; M2Book can offer to install missing book tools when opened.

The book is the central feature. The current stage is generation of this
alternative chapter layout, with runtime metadata enriching the baseline.
Over time, its explanations and organization may be substantially revised by
hand. The generated Markdown provides a starting point for that editorial work.

The split from [MarkdownDocs](https://github.com/AlexanderGolys/MarkdownDocs) is
intentional. MarkdownDocs offers essentially the original documentation-browsing
experience through a different rendering engine: Markdown and mdBook in place of
the original HTML presentation. It preserves the original content and
organization, with improved typography and graphics, and offers browser access
to local package documentation similar to Core's `viewHelp`.

M2Book uses that faithful edition as a starting point for an alternative
presentation. Rewritten explanations, expanded coverage, editorial preferences,
and structural reorganization all belong here. Keeping the faithful edition in
MarkdownDocs allows the book to develop independently.

Generation supplies a starting point for authoring the book. Subsequent work can
involve extensive manual rewrites as well as structural changes implemented by
the package. For example, M2Book groups a method function's installations into
sections of its reference page and redirects links to those sections. The
package maintains that layout and link transformation; the explanations can be
written and improved by hand.

Runtime inspection supplies information missing from the original documentation,
including facts held in internal hash tables. Method signatures, options, type
relationships, mutability, and source definitions enrich the baseline and support
further editing. Metadata export for tools such as m2-ls is a secondary use of
that work.

## Book layout

Where the installed documentation has a page for each documentation node, the
book has a page for each object:

- the methods installed on a function, documented or not, are sections of the
  `Installations` chapter of its page;
- the methods a package installs on a function documented elsewhere are sections
  of a page made for that function in the package;
- an exported symbol without documentation has a page of its own;
- each page opens with its details (class or ancestors, aliases, package, inputs
  and outputs), and the table of contents groups the exports of the main page.

```m2
needsPackage "M2Book"

mdBook "Graphs"   -- generate a baseline book, serve it and open it in the browser

needsPackage "Graphs"
render mdBookPage (degree, Digraph, Thing)   -- Graphs' page for degree

-- book/Graphs: index.md, contents.md, a page per object, images/
writeMdBook("Graphs", "book", LinkedPackages => {"Macaulay2Doc"})
writeBookFiles "book/Graphs"
```

A link to a method points at the heading of its section:
`_degree.md#degreedigraphthing`, or `[[Graphs/_degree#degree(Digraph,Thing)]]`
with `LinkStyle => "wikilink"`. The directory layout, links, `LinkedPackages` and
the mdBook configuration are those of MarkdownDocs.

These commands generate the baseline layout from local documentation; they
replace their generated pages when run again. They are useful for previewing the
structural presentation and seeding a book. An edited book should be maintained
through targeted updates that preserve its manual rewrites.

`mdBook` writes a package below `~/.Macaulay2/M2Book/`, makes it an mdBook source
and serves it with `mdbook serve` in the background, as MarkdownDocs' `mdDocs`
does for the docs layout.

## Installation

M2Book needs MarkdownDocs installed. Its viewer uses `mdbook`, `mdbook-tsitter`
for syntax highlighting, and `mdbook-katex` for mathematics. If tools are missing,
`mdBook` asks whether to install them before generating the book.

```m2
installPackage("MarkdownDocs", FileName => "/path/to/MarkdownDocs/MarkdownDocs.m2")
installPackage("M2Book", FileName => "/path/to/M2Book/M2Book.m2")
check "M2Book"
```

Open the book from Macaulay2:

```m2
needsPackage "M2Book"
mdBook "Graphs"       -- asks before installing missing dependencies
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

## Runtime reference and LSP metadata

M2Book includes the extraction API and scripts used to gather documentation and
runtime facts for enrichment. The extracted metadata also serves secondary
consumers such as the m2-ls type checker.
Machine facts remain separate from editable prose so that re-extraction can
preserve documentation improvements.

```sh
# Create a fresh reference baseline and LSP index; replaces reference/src.
./scripts/generate_reference.sh

# Create a smaller baseline, including packages loaded by a fresh M2 session.
./scripts/generate_reference.sh packages=default,Text,JSON
```

Set `M2_BIN` to choose the Macaulay2 executable and `M2BOOK_JOBS` to control the
worker count for a full extraction (default: 4). Full extraction resumes completed
package checkpoints after interruption; `M2BOOK_CHECKPOINT_DIR` can override their
location. Keep a custom checkpoint directory exclusive to one extractor version.

The current development outputs are ignored by git:

- `m2-facts.jsonl`: runtime facts and documentation source information.
- `reference/src/`: reference Markdown pages, including missing documentation
  markers and runtime facts.
- `m2-reference.jsonl`: complete facts with editable documentation overlaid.
- `m2-index.jsonl`: the LSP corpus, with a leading `meta` record containing the
  fresh-session `default_loaded` packages, followed by structural records and
  hover Markdown. Its line schema is [m2-index.schema.json](m2-index.schema.json).

`protected` reports whether an exported symbol can be reassigned (the negation
of `isMutable` on the symbol). `mutable` is `isMutable` on its value. Both are
Boolean fields, or `null` when the query fails. For type records, `mutable`
describes the type object itself, not instances of the type. These facts appear
in reference pages and survive projection into the LSP index.

Object and method records also retain `source_location` (absolute filename and
start/stop rows and columns from `locate`) and `source` (the source lines covering
that span when the file is readable). Missing locations or source text are
`null`, including compiled builtins without a recorded Macaulay2 definition.
Rows are one-based and columns are zero-based, using Macaulay2's native span
convention, with an exclusive stop column. When no implementation location is
recorded, extraction tries the symbol's declaration. Methods retain their own
implementation spans. Source locations and code excerpts also appear in the
reference pages.

The scripts load M2Book directly from this checkout and use the installed
MarkdownDocs dependency. The extraction API is also available after installing
M2Book:

```m2
needsPackage "M2Book"
writeReferenceJSON("m2-facts.jsonl", {}, {"Core"})
```

After editing the reference pages by hand, refresh the runtime facts and
assemble them with the existing prose. Skip Markdown rendering so the edited
pages are preserved:

```sh
M2 --script scripts/extract_m2_facts.m2 m2-facts.jsonl packages=default
M2 --script scripts/assemble_jsonl.m2 reference/src m2-facts.jsonl m2-reference.jsonl m2-index.jsonl
```

The regenerated `m2-index.jsonl` can replace the LSP's `src/data/m2-index.jsonl`.

Validate the reference pipeline with `python3 -m unittest discover -s tests -v`.
After installing M2Book, `check "M2Book"` checks book rendering and runtime
extraction.

## License

[MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
