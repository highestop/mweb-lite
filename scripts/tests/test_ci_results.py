"""Exercise the result contract independently of native app tests."""
import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from ci_results import catalog, collect, evidence_prefix, render, validate_rows


class ResultsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        self.xctest = self.root / "xctest.jsonl"
        self.preview = self.root / "preview.jsonl"
        self.prefix = evidence_prefix("https://github.com/example/app/actions/runs/123", "a" * 40, 2)
        self.selector = "LibraryTests/test_LIB_001_Load"
        self.cases = {
            "LIB-001": {"Path": "CI", "Verification": self.selector},
            "PV-001": {"Path": "CI", "Verification": "preview"},
            "PV-005": {"Path": "Local script", "Verification": "preview"},
        }

    def write(self, path, rows):
        path.write_text("".join(json.dumps(row) + "\n" for row in rows))

    def row(self, identifier, status="Passed", detail="assertions passed"):
        return dict(case_id=identifier, status=status, evidence=detail)

    def test_collects_per_case_failures_and_excludes_local_only_cases(self):
        self.write(self.xctest, [self.row("LIB-001", "Failed", self.selector + ": expected 2, received 1")])
        self.write(self.preview, [self.row("PV-001", "Passed"), self.row("PV-005", "Skipped")])
        rows = collect(self.xctest, self.preview, self.cases, self.prefix, True, True)
        self.assertEqual([r["case_id"] for r in rows], ["LIB-001", "PV-001"])
        self.assertEqual([r["status"] for r in rows], ["Failed", "Passed"])
        self.assertTrue(all(set(row) == {"case_id", "status", "evidence"} for row in rows))
        self.assertIn("attempts/2", rows[0]["evidence"])

    def test_skip_is_not_a_pass(self):
        self.write(self.xctest, [self.row("LIB-001", "Skipped", self.selector + ": unsupported environment")])
        self.assertEqual(collect(self.xctest, self.preview, self.cases, self.prefix)[0]["status"], "Skipped")

    def test_missing_or_partial_output_does_not_invent_results(self):
        self.assertEqual(collect(self.xctest, self.preview, self.cases, self.prefix), [])
        self.write(self.preview, [self.row("PV-001", "Failed")])
        self.assertEqual(len(collect(self.xctest, self.preview, self.cases, self.prefix)), 1)
        with self.assertRaisesRegex(ValueError, "Successful XCTest runner omitted"):
            collect(self.xctest, self.preview, self.cases, self.prefix, require_xctest=True)
        self.preview.unlink()
        with self.assertRaisesRegex(ValueError, "Successful preview runner omitted"):
            collect(self.xctest, self.preview, self.cases, self.prefix, require_preview=True)

    def test_wrong_selector_unknown_case_and_duplicates_are_rejected(self):
        for rows in ([self.row("LIB-001", detail="LibraryTests/test_LIB_002_Wrong")],
                     [self.row("LIB-999", detail=self.selector)],
                     [self.row("LIB-001", detail=self.selector)] * 2):
            with self.subTest(rows=rows):
                self.write(self.xctest, rows)
                with self.assertRaises(ValueError):
                    collect(self.xctest, self.preview, self.cases, self.prefix)

    def test_invalid_schema_cannot_enter_artifact(self):
        valid = self.row("PV-001", detail=self.prefix + " — checked")
        invalid = [dict(valid, extra=True), dict(valid, status="Pending"), dict(valid, case_id="PV-005"),
                   dict(valid, evidence="line\nbreak"), dict(valid, case_id=[]), dict(valid, status=[]),
                   dict(valid, evidence=" "), dict(valid, evidence="x" * 4001)]
        for row in invalid:
            with self.subTest(row=row):
                with self.assertRaises(ValueError):
                    validate_rows([row], self.cases, self.prefix)
        with self.assertRaisesRegex(ValueError, "trusted run"):
            validate_rows([dict(valid, evidence="different run")], self.cases, self.prefix)
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            validate_rows([valid, valid], self.cases, self.prefix)

    def test_shared_run_precedes_table_and_details_remain_in_artifact(self):
        diagnostic = "[click](https://bad.example) | <script> & `text`"
        rows = [self.row("PV-001", detail=self.prefix + " — " + diagnostic),
                self.row("LIB-001", "Failed", self.prefix + " — assertion failed")]
        original = json.dumps(rows)
        result = render(rows, self.cases, self.prefix)
        self.assertIn("[PV-001](cases/PV-001.md) | Passed |", result)
        self.assertIn("[LIB-001](cases/LIB-001.md) | Failed |", result)
        run_url = "https://github.com/example/app/actions/runs/123/attempts/2"
        self.assertEqual(result.count(run_url), 1)
        self.assertLess(result.index(run_url), result.index("| Case ID | Status |"))
        self.assertIn("https://github.com/example/app/commit/" + "a" * 40, result)
        self.assertNotIn("Evidence", result)
        self.assertNotIn(diagnostic, result)
        self.assertEqual(json.dumps(rows), original)
        self.assertTrue(all(line.count("|") == 3 for line in result.splitlines() if line.startswith("|")))

    def test_summary_cannot_label_results_from_different_runs_with_one_link(self):
        other = evidence_prefix("https://github.com/example/app/actions/runs/124", "b" * 40, 1)
        rows = [self.row("PV-001", detail=self.prefix + " — checked"),
                self.row("LIB-001", detail=other + " — checked")]
        with self.assertRaisesRegex(ValueError, "trusted run"):
            render(rows, self.cases, self.prefix)
        with self.assertRaisesRegex(ValueError, "canonical shared CI run"):
            render([], self.cases, "invalid link")

    def test_catalog_has_explicit_ci_selectors_and_known_preview_scope(self):
        cases = catalog()
        ci = {identifier: case for identifier, case in cases.items() if case["Path"] == "CI"}
        self.assertTrue(ci)
        self.assertEqual({identifier for identifier in ci if identifier.startswith("PV-")},
                         {"PV-001", "PV-002", "PV-003", "PV-004", "PV-006", "PV-007"})
        self.assertTrue(all("Status" not in case and "Evidence" not in case for case in cases.values()))


if __name__ == "__main__":
    unittest.main()
