-- Render one editable reference page per record of a facts file; the page
-- format is described in M2Book/reference/pages.m2.
--
-- Usage:
--   M2 --script scripts/render_markdown.m2 [m2-facts.jsonl] [book/src]

load "./load_package.m2"
importFrom("M2Book", {"writeReferencePages"})

args := drop(scriptCommandLine, 1);
writeReferencePages(
    if #args > 0 then args#0 else "m2-facts.jsonl",
    if #args > 1 then args#1 else "book/src")
