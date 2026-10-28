"""Check runtime facts through Markdown rendering and LSP projection."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def read_records(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line]


def run_script(name, *arguments):
    return subprocess.run(
        [os.environ.get("M2_BIN", "M2"), "--script",
         str(ROOT / "scripts" / name), *map(str, arguments)],
        cwd=ROOT, check=True, capture_output=True, text=True,
    )


class ReferencePipelineTest(unittest.TestCase):
    def test_invalid_source_spans_are_recovered(self):
        with tempfile.TemporaryDirectory(prefix="m2book-sources-") as directory:
            directory = Path(directory)
            facts = directory / "facts.jsonl"
            enriched = directory / "enriched.jsonl"
            invalid = {"filename": "unavailable", "start_row": "not a row",
                       "start_col": 0, "stop_row": 1, "stop_col": 0}
            generated = {"filename": "currentString", "start_row": 1,
                         "start_col": 0, "stop_row": 1, "stop_col": 5}
            facts.write_text(json.dumps({
                "name": "pi", "package": "Core", "source_location": invalid,
                "source": "invalid", "methods": [
                    {"source_location": invalid, "source": "invalid"},
                    {"source_location": generated, "source": None},
                ],
            }) + "\n" + json.dumps({
                "name": "missingObject", "package": "UnavailableReferenceSourcePackage",
            }) + "\n")
            run_script("enrich_sources.m2", facts, enriched)
            record, missing = read_records(enriched)
            self.assertIsInstance(record["source_location"]["start_row"], int)
            self.assertTrue(Path(record["source_location"]["filename"]).is_absolute())
            self.assertNotEqual(record["source"], "invalid")
            self.assertIsNone(record["methods"][0]["source_location"])
            self.assertIsNone(record["methods"][0]["source"])
            self.assertIsNone(record["methods"][1]["source_location"])
            self.assertEqual(missing["name"], "missingObject")
            self.assertIsNone(missing["source_location"])
            self.assertIsNone(missing["source"])

    def test_source_locations_skip_core_wrappers(self):
        with tempfile.TemporaryDirectory(prefix="m2book-locations-") as directory:
            facts = Path(directory) / "facts.jsonl"
            run_script("extract_m2_facts.m2", facts, "packages=Core",
                       "End", "method", "errorDepth", "ascii", "+")
            by_name = {record["name"]: record for record in read_records(facts)}
            # Functions with options are located at their body, not Core's wrapper.
            self.assertTrue(by_name["End"]["source_location"]["filename"].endswith("/Hom.m2"))
            self.assertIn("End =", by_name["End"]["source"])
            self.assertIn("method =", by_name["method"]["source"])
            # An integer value is not an index into the last `methods` listing.
            error_depth = by_name["errorDepth"]
            self.assertTrue(error_depth["source_location"] is None
                            or "errorDepth" in error_depth["source"])
            # Typical-value declarations on a compiled function have no definition.
            self.assertTrue(by_name["ascii"]["methods"])
            for method in by_name["ascii"]["methods"]:
                self.assertIsNone(method["source_location"])
            # So do those Core installs on keywords; real operator methods keep theirs.
            plus_locations = [method["source_location"]["filename"]
                              for method in by_name["+"]["methods"]
                              if method["source_location"]]
            self.assertTrue(plus_locations)
            self.assertFalse([filename for filename in plus_locations
                              if filename.endswith("/m2/typicalvalues.m2")])

    def test_mutability_and_signatures_survive_the_pipeline(self):
        with tempfile.TemporaryDirectory(prefix="m2book-reference-") as directory:
            directory = Path(directory)
            facts = directory / "facts.jsonl"
            pages = directory / "pages"
            reference = directory / "reference.jsonl"
            index = directory / "index.jsonl"

            run_script("extract_m2_facts.m2", facts, "packages=Core",
                       "ZZ", "Type", "allowableThreads", "pi", "path", "degree")
            records = read_records(facts)
            by_name = {record["name"]: record for record in records}
            self.assertEqual(set(by_name),
                             {"ZZ", "Type", "allowableThreads", "pi", "path", "degree"})
            self.assertIs(by_name["ZZ"]["mutable"], False)
            self.assertIs(by_name["Type"]["mutable"], False)
            self.assertIs(by_name["Type"]["protected"], True)
            self.assertIs(by_name["allowableThreads"]["mutable"], True)
            self.assertIs(by_name["allowableThreads"]["protected"], False)
            self.assertIs(by_name["path"]["mutable"], True)
            self.assertIs(by_name["pi"]["mutable"], False)
            self.assertIs(by_name["ZZ"]["protected"], True)
            self.assertIs(by_name["path"]["protected"], False)
            self.assertTrue(by_name["degree"]["methods"])
            method_sources = [method for method in by_name["degree"]["methods"]
                              if method.get("source_location") and method.get("source")]
            self.assertTrue(method_sources)

            # Unknown runtime queries must stay unknown in the projected corpus.
            by_name["path"]["mutable"] = None
            facts.write_text("".join(json.dumps(record) + "\n" for record in records))
            run_script("render_markdown.m2", facts, pages)
            run_script("assemble_jsonl.m2", pages, facts, reference, index)

            compiled = read_records(index)
            self.assertEqual(compiled[0]["kind"], "meta")
            baseline_script = directory / "baseline.m2"
            baseline_script.write_text(
                'scan(sort apply(loadedPackages, toString), print); exit 0\n'
            )
            baseline = subprocess.run(
                [os.environ.get("M2_BIN", "M2"), "--script", str(baseline_script)],
                cwd=ROOT, check=True, capture_output=True, text=True,
            ).stdout.splitlines()
            self.assertEqual(compiled[0]["default_loaded"], baseline)
            self.assertEqual(len(compiled), len(records) + 1)
            result = {record["name"]: record for record in compiled[1:]}
            for name, record in by_name.items():
                self.assertIs(result[name]["mutable"], record["mutable"])
                self.assertIs(result[name]["protected"], record["protected"])
                self.assertEqual(result[name]["source_location"], record["source_location"])
                self.assertEqual(result[name]["source"], record["source"])
                self.assertEqual(len(result[name].get("methods", [])),
                                 len(record.get("methods", [])))
                for before, after in zip(record.get("methods", []),
                                         result[name].get("methods", [])):
                    self.assertEqual(after["source_location"], before["source_location"])
                    self.assertEqual(after["source"], before["source"])
            self.assertIn("**Mutable:** false", result["ZZ"]["markdown"])
            self.assertIn("**Mutable:** false", result["Type"]["markdown"])
            self.assertIn("**Mutable:** true", result["allowableThreads"]["markdown"])
            self.assertIn("**Mutable:** false", result["pi"]["markdown"])
            self.assertIn("**Protected:** false", result["path"]["markdown"])
            self.assertNotIn("**Mutable:**", result["path"]["markdown"])
            self.assertIn("**Defined at:**", result["degree"]["markdown"])
            self.assertIn("#### Source", result["degree"]["markdown"])
            self.assertIn(method_sources[0]["source"], result["degree"]["markdown"])
            for record in read_records(reference):
                for method in record.get("methods", []):
                    self.assertNotIn("#### Source", method.get("description", ""))


if __name__ == "__main__":
    unittest.main()
