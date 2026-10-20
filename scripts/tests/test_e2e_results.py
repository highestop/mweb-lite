import copy
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from e2e_results import HistoryError, REPORT_PATH, RESULT_PATHS, effective_commit, read_rows, refresh, render

CASES = {"E2E-001": {"Level": "End-to-end"}, "REL-001": {"Level": "End-to-end"}, "LIB-001": {"Level": "Integration"}}
SHA = "a" * 40


def blank_rows():
    return [dict(case_id=identifier, status="—", commit_sha="—", outdated="—")
            for identifier in ("E2E-001", "REL-001")]


class TableTests(unittest.TestCase):
    def test_unrecorded_and_recorded_rows_round_trip(self):
        rows = blank_rows()
        self.assertEqual(read_rows(render(rows, CASES), CASES), rows)
        for status in ("Passed", "Failed", "Skipped"):
            for outdated in ("", "Yes"):
                rows[0].update(status=status, commit_sha=SHA, outdated=outdated)
                self.assertEqual(read_rows(render(rows, CASES), CASES), rows)

    def test_invalid_values_and_partial_unrecorded_rows_are_rejected(self):
        for changes in ({"status": "Pending"}, {"status": "Passed"}, {"outdated": "Yes"},
                        {"status": "Passed", "commit_sha": "abc123", "outdated": ""},
                        {"status": "Passed", "commit_sha": SHA, "outdated": "No"},
                        {"status": None}, {"extra": "not allowed"}):
            with self.subTest(changes=changes):
                rows = blank_rows()
                rows[0].update(changes)
                with self.assertRaises(ValueError):
                    render(rows, CASES)

    def test_missing_duplicate_non_e2e_and_unknown_cases_are_rejected(self):
        for rows in (blank_rows()[:1], blank_rows() + [blank_rows()[0]],
                     [dict(blank_rows()[0], case_id="LIB-001"), blank_rows()[1]],
                     [dict(blank_rows()[0], case_id="E2E-999"), blank_rows()[1]]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                render(rows, CASES)

    def test_bad_title_links_columns_and_bare_sha_are_rejected(self):
        rows = blank_rows()
        rows[0].update(status="Passed", commit_sha=SHA, outdated="")
        text = render(rows, CASES)
        for invalid in (text.replace("# E2E test result", "# Results"),
                        text.replace("cases/E2E-001.md", "cases/REL-001.md"),
                        text.replace("| Passed |", "| Passed | extra |"),
                        text.replace(f"`{SHA}`", SHA), text + "Unstructured note\n"):
            with self.subTest(text=invalid), self.assertRaises(ValueError):
                read_rows(invalid, CASES)


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="mweb-e2e-results-")
        self.addCleanup(self.directory.cleanup)
        self.repo = pathlib.Path(self.directory.name) / "repository"
        self.repo.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Result Tests")
        self.git("config", "user.email", "result-tests@example.invalid")
        self.base = self.commit({"Sources/example.swift": "version 1\n"})

    def git(self, *arguments):
        return subprocess.run(["git", "-C", str(self.repo), *arguments], check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, files=None, message="test commit"):
        for name, content in (files or {}).items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.git("add", "--all")
        self.git("commit", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def recorded(self, sha=None, status="Passed", outdated=""):
        rows = blank_rows()
        rows[0].update(status=status, commit_sha=sha or self.base, outdated=outdated)
        return rows

    def test_result_only_chain_is_ignored_and_status_sha_are_preserved(self):
        ci_report = "docs/testing/ci-test-result.md"
        self.commit({ci_report: "first CI results\n"})
        first_manual = self.commit({REPORT_PATH: "manual result\n"})
        latest = self.commit({ci_report: "second CI results\n", REPORT_PATH: "refreshed flag\n"})
        self.assertEqual(effective_commit(self.repo, latest), self.base)
        for tested in (self.base, first_manual, latest):
            rows = self.recorded(tested, status="Failed", outdated="Yes")
            original = copy.deepcopy(rows)
            updated = refresh(rows, self.repo, "main")
            self.assertEqual(updated[0], dict(rows[0], outdated=""))
            self.assertEqual(updated[1], rows[1])
            self.assertEqual(rows, original)
        self.assertEqual(RESULT_PATHS, frozenset({ci_report, REPORT_PATH}))

    def test_code_and_mixed_changes_mark_old_results_outdated(self):
        code = self.commit({"Sources/example.swift": "version 2\n"})
        self.assertEqual(refresh(self.recorded(), self.repo, code)[0]["outdated"], "Yes")
        mixed = self.commit({REPORT_PATH: "report\n", "Sources/example.swift": "version 3\n"})
        self.assertEqual(effective_commit(self.repo, mixed), mixed)
        self.assertEqual(refresh(self.recorded(code), self.repo, mixed)[0]["outdated"], "Yes")
        self.assertEqual(refresh(self.recorded(mixed, outdated="Yes"), self.repo, mixed)[0]["outdated"], "")

    def test_titles_authors_empty_commits_and_other_docs_are_not_exempt(self):
        self.git("config", "user.name", "github-actions[bot]")
        empty = self.commit(message="docs: update CI test results")
        self.assertEqual(effective_commit(self.repo, empty), empty)
        other = self.commit({"docs/testing/test-guide.md": "guide change\n"}, message="report only")
        self.assertEqual(effective_commit(self.repo, other), other)
        self.assertEqual(refresh(self.recorded(), self.repo, other)[0]["outdated"], "Yes")

    def test_merges_use_first_parent_diff(self):
        self.git("checkout", "-b", "reports")
        self.commit({REPORT_PATH: "report from side branch\n"})
        self.git("checkout", "main")
        meaningful = self.commit({"Sources/example.swift": "main change\n"})
        self.git("merge", "--no-ff", "reports", "-m", "merge report")
        self.assertEqual(effective_commit(self.repo, "HEAD"), meaningful)
        self.git("checkout", "-b", "code")
        self.commit({"Sources/feature.swift": "feature\n"})
        self.git("checkout", "main")
        self.commit({REPORT_PATH: "new result\n"})
        self.git("merge", "--no-ff", "code", "-m", "merge code")
        merge = self.git("rev-parse", "HEAD")
        self.assertEqual(effective_commit(self.repo, merge), merge)

    def test_different_tested_history_is_outdated_even_if_trees_match(self):
        self.git("checkout", "-b", "other-history")
        self.commit({"Sources/example.swift": "changed temporarily\n"})
        other = self.commit({"Sources/example.swift": "version 1\n"})
        self.git("checkout", "main")
        self.assertEqual(self.git("rev-parse", other + "^{tree}"), self.git("rev-parse", self.base + "^{tree}"))
        self.assertEqual(refresh(self.recorded(other), self.repo, "main")[0]["outdated"], "Yes")

    def test_rename_outside_result_paths_is_meaningful(self):
        report = self.commit({REPORT_PATH: "report\n"})
        self.git("mv", REPORT_PATH, "docs/testing/moved-report.md")
        renamed = self.commit()
        self.assertEqual(effective_commit(self.repo, report), self.base)
        self.assertEqual(effective_commit(self.repo, renamed), renamed)

    def test_missing_tested_commit_is_outdated_but_missing_head_is_an_error(self):
        self.assertEqual(refresh(self.recorded("f" * 40), self.repo, "main")[0]["outdated"], "Yes")
        with self.assertRaises(HistoryError):
            refresh(self.recorded(), self.repo, "missing-ref")

    def test_unrecorded_rows_stay_unrecorded_and_dirty_files_are_not_test_results(self):
        rows = blank_rows()
        (self.repo / "Sources/example.swift").write_text("uncommitted code\n")
        self.assertEqual(refresh(rows, self.repo, "main"), rows)
        self.assertEqual(refresh(self.recorded(outdated="Yes"), self.repo, "main")[0]["outdated"], "")
        self.assertEqual((self.repo / "Sources/example.swift").read_text(), "uncommitted code\n")

    def test_shallow_history_is_rejected(self):
        self.commit({REPORT_PATH: "report\n"})
        clone = pathlib.Path(self.directory.name) / "shallow"
        subprocess.run(["git", "clone", "--depth=1", self.repo.as_uri(), str(clone)], check=True, capture_output=True)
        with self.assertRaisesRegex(HistoryError, "full Git history"):
            effective_commit(clone, "HEAD")

    def prepare_cli(self):
        destination = self.repo / "scripts"
        destination.mkdir()
        for name in ("update-e2e-results.py", "e2e_results.py", "ci_results.py", "check-test-cases.py"):
            shutil.copyfile(SCRIPTS / name, destination / name)
        for identifier in ("E2E-001", "REL-001"):
            source = self.repo / "docs/testing/cases" / (identifier + ".md")
            source.parent.mkdir(parents=True, exist_ok=True)
            fields = {"ID": identifier, "Verification": "Manual fixture", "Given": "Fixture", "When": "Open app",
                      "Then": "Visible state", "Level": "End-to-end", "Path": "Preview app", "Data": "Inline"}
            source.write_text("| Field | Content |\n| --- | --- |\n" + "".join(f"| {key} | {value} |\n" for key, value in fields.items()))
        (self.repo / REPORT_PATH).write_text(render(blank_rows(), CASES))
        return destination / "update-e2e-results.py"

    def cli(self, script, *arguments):
        return subprocess.run([sys.executable, str(script), *arguments], capture_output=True, text=True)

    def test_cli_check_does_not_resolve_head_or_write_and_refresh_only_changes_flags(self):
        script = self.prepare_cli()
        rows = self.recorded(outdated="Yes")
        report = self.repo / REPORT_PATH
        report.write_text(render(rows, CASES))
        before = report.read_bytes()
        result = self.cli(script, "--check", "--head-ref", "does-not-exist")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(report.read_bytes(), before)
        result = self.cli(script, "--refresh", "--head-ref", "main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(read_rows(report.read_text(), CASES), refresh(rows, self.repo, "main"))

    def test_cli_records_only_supplied_case_and_requires_explicit_commit(self):
        script = self.prepare_cli()
        report = self.repo / REPORT_PATH
        before = report.read_bytes()
        for arguments in (("--case", "E2E-001", "--status", "Passed"),
                          ("--case", "E2E-001", "--status", "Passed", "--commit", "HEAD"),
                          ("--check", "--case", "E2E-001", "--status", "Passed", "--commit", self.base)):
            result = self.cli(script, *arguments)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(report.read_bytes(), before)
        result = self.cli(script, "--case", "E2E-001", "--status", "Skipped", "--commit", self.base, "--head-ref", "main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no test was run", result.stdout)
        self.assertEqual(read_rows(report.read_text(), CASES), self.recorded(status="Skipped"))


if __name__ == "__main__":
    unittest.main()
