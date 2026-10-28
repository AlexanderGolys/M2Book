-- Overlay the reference pages on the facts they were rendered from, writing the
-- full reference corpus and the LSP index; described in M2Book/reference/index.m2.
--
-- Usage:
--   M2 --script scripts/assemble_jsonl.m2 [book/src] [m2-facts.jsonl] \
--       [m2-reference.jsonl] [m2-index.jsonl]

load "./load_package.m2"
importFrom("M2Book", {"assembleReference", "freshSessionPackages"})

args := drop(scriptCommandLine, 1);
assembleReference(
    if #args > 0 then args#0 else "book/src",
    if #args > 1 then args#1 else "m2-facts.jsonl",
    if #args > 2 then args#2 else "m2-reference.jsonl",
    if #args > 3 then args#3 else "m2-index.jsonl",
    freshSessionPackages())
