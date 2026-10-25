#!/usr/bin/env bash
# Extract runtime facts, render reference pages, and assemble the LSP corpus.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
m2="${M2_BIN:-$(command -v M2)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/m2book-reference-XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

if (( $# == 0 )); then
    "$root/scripts/extract_all_packages.sh" m2-facts.jsonl
else
    "$m2" --script scripts/extract_m2_facts.m2 m2-facts.jsonl "$@"
fi

"$m2" --script scripts/render_markdown.m2 m2-facts.jsonl "$work/pages"
"$m2" --script scripts/assemble_jsonl.m2 "$work/pages" m2-facts.jsonl \
    "$work/reference.jsonl" "$work/index.jsonl"

mkdir -p reference
if [[ -e reference/src ]]; then
    mv -- reference/src "$work/previous-pages"
fi
mv -- "$work/pages" reference/src
mv -- "$work/reference.jsonl" m2-reference.jsonl
mv -- "$work/index.jsonl" m2-index.jsonl
