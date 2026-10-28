# Curated book sources

Only edited pages and assets are kept here. The generated documentation for
unchanged pages is supplied at build time from the installed packages.

Put an edited page at the same relative path as its generated counterpart:
`curated/Graphs/_add__Vertex.md`, for example. Commit the edited page and any
assets it needs. Do not copy an entire generated package here.

From Macaulay2 with M2Book loaded from this checkout:

```m2
viewM2Book "Graphs"
viewCuratedM2Book "Graphs"
```

The standard mdBook title identifies each edition as `Graphs — Generated` or
`Graphs — Curated`. Both can remain open simultaneously.

To build without opening the browser:

```m2
writeCuratedM2Book("Graphs", "book/curated")
```

When using an installed M2Book, pass the repository explicitly:

```m2
viewCuratedM2Book("Graphs", "/path/to/M2Book")
writeCuratedM2Book("Graphs", "book/curated", "/path/to/M2Book")
```

The build regenerates the baseline in its destination and then overlays the
files in `curated/<package>/`. It never writes to these source files. A package
without overrides has the same content as the generated edition.

Overrides replace whole files. Renderer updates flow into unchanged pages;
changes relevant to an edited page must be merged into it by hand. Keep the
generated edition open alongside the curated edition to compare them. Removing
an override restores the generated page on the next build.

An edited `SUMMARY.md` or `book.css` can also be overlaid when needed. Additional
pages must be linked from the summary or another page. If overriding `book.toml`,
retain the edition in its title. `contents.md` is an intermediate file: edit
`SUMMARY.md` to change the curated book's navigation.
