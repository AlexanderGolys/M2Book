# Curated book sources

Only edited pages and assets are kept here. The generated documentation for
unchanged pages is supplied at build time from the installed packages.

Put an edited page at the same relative path as its generated counterpart:
`Graphs/_add__Vertex.md`, for example. Commit the edited page and any assets it
needs. Do not copy an entire generated package here.

From Macaulay2, with M2Book loaded from this checkout:

```m2
viewBook "Graphs"                            -- the curated edition
viewBook("Graphs", Edition => "Generated")   -- its generated baseline
```

The standard mdBook title identifies each edition as `Graphs — Curated` or
`Graphs — Generated`. Both can remain open simultaneously. To start editing a
page, write the generated edition and copy the page here:

```m2
generateBookBase("Graphs", "book")
```

A curated build regenerates the baseline in its destination and then overlays
the files in `<package>/`. It never writes to these source files. A package
without overrides has the same content as the generated edition. The directory
is installed with the package, so an installed M2Book shows its curated pages
too.

Overrides replace whole files. Renderer updates flow into unchanged pages;
changes relevant to an edited page must be merged into it by hand. Keep the
generated edition open alongside the curated edition to compare them. Removing
an override restores the generated page on the next build.

An edited `SUMMARY.md` or `book.css` can also be overlaid when needed. Additional
pages must be linked from the summary or another page. If overriding `book.toml`,
retain the edition in its title. `contents.md` is an intermediate file: edit
`SUMMARY.md` to change the curated book's navigation.
