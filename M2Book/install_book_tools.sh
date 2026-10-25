#!/usr/bin/env bash
# Install the book renderer and preprocessors, then prepare their grammars.
set -euo pipefail

if (( $# != 0 )); then
    echo "Usage: $0" >&2
    echo "Set M2BOOK_TOOLS_ROOT to choose an installation prefix." >&2
    exit 2
fi

original_path="$PATH"
cargo_bin="${CARGO_HOME:-$HOME/.cargo}/bin"
install_root="${M2BOOK_TOOLS_ROOT:-${CARGO_INSTALL_ROOT:-${CARGO_HOME:-$HOME/.cargo}}}"
bin_dir="$install_root/bin"
export PATH="$PATH:$bin_dir:$cargo_bin"

work="$(mktemp -d "${TMPDIR:-/tmp}/m2book-tools-XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

missing_tools=()
for tool in mdbook mdbook-tsitter mdbook-katex; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "Using $tool: $(command -v "$tool")"
    else
        missing_tools+=("$tool")
    fi
done

if (( ${#missing_tools[@]} > 0 )); then
    if ! command -v cargo >/dev/null 2>&1; then
        if ! command -v curl >/dev/null 2>&1; then
            echo "Installing Rust and Cargo requires curl. Install curl or Cargo, then rerun setup." >&2
            exit 1
        fi
        echo "Installing a minimal stable Rust toolchain, including Cargo, using rustup."
        curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
            https://sh.rustup.rs --output "$work/rustup-init.sh"
        sh "$work/rustup-init.sh" -y --profile minimal --default-toolchain stable --no-modify-path
        if ! command -v cargo >/dev/null 2>&1; then
            echo "Rust setup finished but Cargo is still unavailable in $cargo_bin." >&2
            exit 1
        fi
    fi
    for tool in "${missing_tools[@]}"; do
        cargo install --locked --root "$install_root" "$tool"
    done
fi

path_additions=""
for directory in "$bin_dir" "$cargo_bin"; do
    if [[ -d "$directory" && ":$original_path:" != *":$directory:"* \
        && ":$path_additions:" != *":$directory:"* ]]; then
        path_additions="${path_additions:+$path_additions:}$directory"
    fi
done
if [[ -n "$path_additions" ]]; then
    printf 'To use the installed tools from your shell:\n  export PATH=%q:"$PATH"\n' "$path_additions"
fi

# A real build fetches and compiles the grammars through tsitter and checks that
# both preprocessors work with the installed renderer. It leaves the book alone.
mkdir -p "$work/src"
cat > "$work/book.toml" <<'TOML'
[book]
title = "Book tools check"
src = "src"

[preprocessor.katex]

[preprocessor.tsitter]

[preprocessor.tsitter.languages.macaulay2]
aliases = ["m2", "macaulay2"]

[preprocessor.tsitter.languages.bibtex]
aliases = ["bib", "bibtex"]
TOML
cat > "$work/src/SUMMARY.md" <<'MARKDOWN'
# Summary

- [Check](check.md)
MARKDOWN
cat > "$work/src/check.md" <<'MARKDOWN'
# Check

$x^2$

```m2
R = QQ[x];
```

```bibtex
@book{example, title = {Example}}
```
MARKDOWN

echo "Checking math rendering and preparing the Macaulay2 and BibTeX parsers."
if ! mdbook build "$work"; then
    echo "Book tools check failed. Fetching grammars needs network access, Git and a C compiler." >&2
    exit 1
fi
if ! grep -q 'class="katex' "$work/book/check.html" \
    || ! grep -q 'class="treesitter' "$work/book/check.html"; then
    echo "Book tools check failed: math rendering or tree-sitter highlighting is missing." >&2
    exit 1
fi
echo "Book tools and parsers are ready."
