#!/usr/bin/env bash
# Command-line entry point for the installer bundled with M2Book.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$root/M2Book/install_book_tools.sh" "$@"
