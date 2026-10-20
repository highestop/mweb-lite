"""Check automatic freshness publication using real Git history and a fake API."""
import base64
import copy
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from ci_publish import PublishError
from e2e_publish import CI_PUBLISH_NAME, CI_PUBLISH_WORKFLOW, E2EPublisher
from e2e_results import REPORT_PATH, read_rows, render

REPOSITORY = "owner/project"
CASES = {identifier: {"Level": "End-to-end", "Path": "Preview app"}
         for identifier in ("E2E-001", "E2E-002", "E2E-003")}


class FakeAPI:
    def __init__(self, base, text, run):
        self.base, self.text, self.run = base, text, run
        self.calls = []

    def request(self, path, method="GET", payload=None, binary=False):
        self.calls.append((path, method, payload))
        if method != "GET":
            raise AssertionError("Unexpected direct API write")
        prefix = f"repos/{REPOSITORY}"
        if path == prefix:
            return {"full_name": REPOSITORY, "default_branch": "main"}
        if path == prefix + "/git/ref/heads/main":
            return {"object": {"sha": self.base}}
        if path == prefix + "/actions/runs/123":
            return copy.deepcopy(self.run)
        if path.startswith(prefix + f"/contents/{REPORT_PATH}?ref="):
            data = self.text.encode()
            return {"type": "file", "encoding": "base64", "size": len(data),
                    "content": base64.b64encode(data).decode()}
        raise AssertionError(path)


class E2EPublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = pathlib.Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        (self.repo / "app.swift").write_text("old\n")
        self.old = self.commit()
        (self.repo / "app.swift").write_text("new\n")
        self.source = self.commit()
        self.rows = [dict(case_id="E2E-001", status="Passed", commit_sha=self.old, outdated=""),
                     dict(case_id="E2E-002", status="Failed", commit_sha=self.source, outdated="Yes"),
                     dict(case_id="E2E-003", status="—", commit_sha="—", outdated="—")]
        report = self.repo / REPORT_PATH
        report.parent.mkdir(parents=True)
        report.write_text(render(self.rows, CASES))
        self.base = self.commit()
        self.run = {"id": 123, "status": "completed", "conclusion": "success",
                    "event": "workflow_run", "name": CI_PUBLISH_NAME,
                    "path": CI_PUBLISH_WORKFLOW, "head_branch": "main", "run_attempt": 1,
                    "head_sha": self.source, "repository": {"full_name": REPOSITORY},
                    "head_repository": {"full_name": REPOSITORY}}
        self.api = FakeAPI(self.base, report.read_text(), self.run)
        self.publisher = E2EPublisher(self.api, REPOSITORY, self.repo, CASES)
        self.event = {"action": "completed", "repository": {"full_name": REPOSITORY},
                      "workflow_run": {"id": 123, "run_attempt": 1, "head_sha": self.source}}

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], stderr=subprocess.DEVNULL, text=True).strip()

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture change")
        return self.git("rev-parse", "HEAD")

    def publish(self, **kwargs):
        return self.publisher.publish("workflow_run", self.event, "refs/heads/main", 456, **kwargs)

    def test_dry_run_changes_only_flags_and_never_writes(self):
        with patch.object(self.publisher.writer, "publish_report") as publish:
            result = self.publish(dry_run=True)
        self.assertEqual(result["outcome"], "dry-run")
        publish.assert_not_called()
        rows = read_rows(result["report"], CASES)
        self.assertEqual([r["outdated"] for r in rows], ["Yes", "", "—"])
        for old, new in zip(self.rows, rows):
            for field in ("case_id", "status", "commit_sha"):
                self.assertEqual(old[field], new[field])
        self.assertTrue(all(method == "GET" for _, method, _ in self.api.calls))

    def test_live_uses_report_only_publisher_and_exact_base_guard(self):
        def publish(**kwargs):
            kwargs["guard"]()
            self.assertEqual(kwargs["base"], self.base)
            self.assertEqual(kwargs["validation_context"], "E2E result validation")
            rows = read_rows(kwargs["report"], CASES)
            self.assertEqual(rows[1]["status"], "Failed")
            self.assertEqual(rows[1]["outdated"], "")
            return {"outcome": "merged"}
        with patch.object(self.publisher.writer, "publish_report", side_effect=publish):
            self.assertEqual(self.publish()["outcome"], "merged")
        self.assertEqual(self.publisher.writer.report_path, REPORT_PATH)

    def test_concurrent_main_update_cannot_overwrite_manual_results(self):
        def publish(**kwargs):
            self.api.base = "f" * 40
            kwargs["guard"]()
        with patch.object(self.publisher.writer, "publish_report", side_effect=publish):
            with self.assertRaisesRegex(PublishError, "preserving newer manual results"):
                self.publish()

    def test_report_only_push_is_ready_but_source_push_defers(self):
        event = {"repository": {"full_name": REPOSITORY}, "ref": "refs/heads/main",
                 "after": self.base, "before": self.source, "deleted": False}
        result = self.publisher.publish("push", event, "refs/heads/main", 456, dry_run=True)
        self.assertEqual(result["outcome"], "dry-run")
        event.update(after=self.source, before=self.old)
        result = self.publisher.publish("push", event, "refs/heads/main", 456, dry_run=True)
        self.assertEqual(result["outcome"], "deferred")

    def test_stale_completed_workflow_is_noop(self):
        self.api.run["head_sha"] = self.old
        self.event["workflow_run"]["head_sha"] = self.old
        self.assertEqual(self.publish()["outcome"], "stale")

    def test_skipped_publisher_defers_but_failed_publisher_can_refresh(self):
        self.api.run["conclusion"] = "skipped"
        with patch.object(self.publisher.writer, "publish_report") as publish:
            self.assertEqual(self.publish()["outcome"], "deferred")
            publish.assert_not_called()
        self.api.run["conclusion"] = "failure"
        self.assertEqual(self.publish(dry_run=True)["outcome"], "dry-run")

    def test_foreign_repository_workflow_attempt_and_branch_are_rejected(self):
        for field, value in (("name", "untrusted"), ("path", ".github/workflows/other.yml"),
                             ("run_attempt", 2), ("head_branch", "feature"),
                             ("status", "in_progress"), ("head_repository", {"full_name": "other/repo"})):
            with self.subTest(field=field):
                self.api.run = dict(self.run, **{field: value})
                with self.assertRaises(PublishError):
                    self.publish()
        self.api.run = self.run
        self.event["repository"]["full_name"] = "other/repo"
        with self.assertRaisesRegex(PublishError, "repository"):
            self.publish()

    def test_manual_trigger_uses_main_and_latest_checkout(self):
        event = {"repository": {"full_name": REPOSITORY}}
        self.assertEqual(self.publisher.publish("workflow_dispatch", event, "refs/heads/main", 456, dry_run=True)["outcome"], "dry-run")
        with self.assertRaisesRegex(PublishError, "default branch"):
            self.publisher.publish("workflow_dispatch", event, "refs/heads/feature", 456, dry_run=True)
        self.api.base = self.source
        with self.assertRaisesRegex(PublishError, "Checkout"):
            self.publish()

    def test_unchanged_flags_do_not_create_a_commit_or_pr(self):
        self.rows[0]["outdated"], self.rows[1]["outdated"] = "Yes", ""
        self.api.text = render(self.rows, CASES)
        with patch.object(self.publisher.writer, "publish_report") as publish:
            self.assertEqual(self.publish()["outcome"], "unchanged")
            publish.assert_not_called()


if __name__ == "__main__":
    unittest.main()
