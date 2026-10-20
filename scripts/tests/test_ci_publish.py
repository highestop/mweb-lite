import base64
import copy
import io
import json
import pathlib
import stat
import sys
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from ci_publish import APIError, GitHub, MAX_JSON_BYTES, MAX_ZIP_BYTES, PublishError, Publisher, artifact_rows
from ci_results import REPORT_PATH, evidence_prefix, render

REPOSITORY = "owner/project"
BASE = "a" * 40
HEAD = "b" * 40
RUN_ID = 123
RUN_URL = f"https://github.com/{REPOSITORY}/actions/runs/{RUN_ID}"
CASES = {"LIB-001": {"Path": "CI"}, "E2E-001": {"Path": "Preview app"}}
ROWS = [{"case_id": "LIB-001", "status": "Passed", "evidence": evidence_prefix(RUN_URL, BASE, 1) + " — assertion passed"}]
EVENT = {"action": "completed", "repository": {"full_name": REPOSITORY},
         "workflow_run": {"id": RUN_ID, "run_attempt": 1, "head_sha": BASE}}


def make_zip(content=None, name="case-results.json", extra=False, symlink=False):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        info = zipfile.ZipInfo(name)
        if symlink:
            info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(info, json.dumps(ROWS).encode() if content is None else content)
        if extra:
            archive.writestr("unexpected.txt", "extra")
    return stream.getvalue()


class FakeAPI:
    def __init__(self):
        self.calls = []
        self.run = {"id": RUN_ID, "event": "push", "status": "completed", "name": "macOS",
                    "path": ".github/workflows/test.yml", "workflow_id": 7, "head_branch": "main",
                    "head_sha": BASE, "run_attempt": 1,
                    "repository": {"full_name": REPOSITORY}, "head_repository": {"full_name": REPOSITORY}}
        self.default_head = BASE
        self.report_path = REPORT_PATH
        self.archive = make_zip()
        self.report = render(ROWS, CASES, evidence_prefix(RUN_URL, BASE, 1))
        self.current_report = None
        self.branch_exists = False
        self.commit_parent = BASE
        self.changed_files = [{"filename": REPORT_PATH, "status": "added"}]
        self.pull_files = self.changed_files
        self.pull_exists = False
        self.merge_error = None
        self.advance_base_after_status = False
        self.advance_base_after_download = None
        self.mutate_head_after_status = False
        self.pull_head = HEAD
        self.pull_base = BASE
        self.pull_branch = "codex/ci-results-123-1"
        self.mergeable = True
        self.mergeable_values = []
        self.expired = False
        self.artifact_size = 1000

    def request(self, path, method="GET", payload=None, binary=False):
        self.calls.append((path, method, payload, binary))
        prefix = f"repos/{REPOSITORY}"
        if path == prefix:
            return {"full_name": REPOSITORY, "default_branch": "main"}
        assert path.startswith(prefix + "/"), path
        suffix = path[len(prefix) + 1:]
        if suffix == f"actions/runs/{RUN_ID}":
            return copy.deepcopy(self.run)
        if suffix == "actions/workflows/7":
            return {"name": "macOS", "path": ".github/workflows/test.yml"}
        if suffix == "git/ref/heads/main":
            return {"object": {"sha": self.default_head}}
        if suffix.startswith("git/ref/heads/codex/"):
            if not self.branch_exists:
                raise APIError("not found", 404)
            return {"object": {"sha": HEAD}}
        if suffix == f"actions/runs/{RUN_ID}/artifacts?per_page=100":
            return {"total_count": 1, "artifacts": [{"id": 8, "name": "ci-case-results", "expired": self.expired,
                                                       "size_in_bytes": self.artifact_size}]}
        if suffix == "actions/artifacts/8/zip":
            assert binary
            if self.advance_base_after_download:
                self.default_head = self.advance_base_after_download
            return self.archive
        if suffix.startswith(f"contents/{self.report_path}?ref="):
            content = self.report if suffix.endswith(HEAD) else self.current_report
            if content is None:
                raise APIError("not found", 404)
            return {"type": "file", "encoding": "base64", "size": len(content.encode()),
                    "content": base64.b64encode(content.encode()).decode()}
        if suffix == f"git/commits/{HEAD}":
            return {"parents": [{"sha": self.commit_parent}]}
        if suffix.startswith("git/commits/"):
            return {"tree": {"sha": "original-tree"}, "parents": []}
        if suffix.startswith("compare/"):
            return {"ahead_by": 1, "behind_by": 0, "files": self.changed_files}
        if suffix == "git/trees" and method == "POST":
            self.report = payload["tree"][0]["content"]
            return {"sha": "new-tree"}
        if suffix == "git/commits" and method == "POST":
            self.commit_parent = payload["parents"][0]
            return {"sha": HEAD}
        if suffix == "git/refs" and method == "POST":
            self.branch_exists = True
            return {"object": {"sha": HEAD}}
        if suffix.startswith("pulls?"):
            return [{"number": 9, "state": "open"}] if self.pull_exists else []
        if suffix == "pulls" and method == "POST":
            self.pull_exists = True
            self.pull_base = self.default_head
            self.pull_branch = payload["head"]
            return {"number": 9}
        if suffix == "pulls/9":
            mergeable = self.mergeable_values.pop(0) if self.mergeable_values else self.mergeable
            return {"state": "open", "draft": False, "mergeable": mergeable,
                    "base": {"ref": "main", "sha": self.pull_base, "repo": {"full_name": REPOSITORY}},
                    "head": {"ref": self.pull_branch, "sha": self.pull_head, "repo": {"full_name": REPOSITORY}}}
        if suffix == "pulls/9/files?per_page=100":
            return self.pull_files
        if suffix == f"statuses/{HEAD}" and method == "POST":
            if self.advance_base_after_status:
                self.default_head = "c" * 40
            if self.mutate_head_after_status:
                self.pull_head = "c" * 40
            return {}
        if suffix == "pulls/9/merge" and method == "PUT":
            if self.merge_error:
                raise self.merge_error
            return {"merged": True}
        if suffix.startswith("git/refs/heads/codex/") and method == "DELETE":
            self.branch_exists = False
            return None
        raise AssertionError((suffix, method, payload))

    @property
    def writes(self):
        return [call for call in self.calls if call[1] != "GET"]


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.api = FakeAPI()
        self.publisher = Publisher(self.api, REPOSITORY, CASES)

    def publish(self, **kwargs):
        return self.publisher.publish(RUN_ID, event=copy.deepcopy(EVENT), checkout_sha=BASE, **kwargs)

    def test_dry_run_validates_and_renders_without_any_write(self):
        result = self.publisher.publish(RUN_ID, dry_run=True)
        self.assertEqual(result["outcome"], "dry-run")
        self.assertIn("LIB-001", result["report"])
        self.assertEqual(self.api.writes, [])

    def test_foreign_pr_wrong_workflow_and_incomplete_runs_are_rejected(self):
        for field, value in [("event", "pull_request"), ("head_branch", "topic"), ("status", "in_progress"),
                             ("path", ".github/workflows/untrusted.yml"), ("name", "Other"),
                             ("repository", {"full_name": "foreign/project"}),
                             ("head_repository", {"full_name": "foreign/project"})]:
            with self.subTest(field=field):
                self.api = FakeAPI()
                self.publisher = Publisher(self.api, REPOSITORY, CASES)
                self.api.run[field] = value
                with self.assertRaises(PublishError):
                    self.publish()
                self.assertEqual(self.api.writes, [])

    def test_stale_source_and_stale_dispatch_attempt_are_rejected(self):
        self.api.default_head = "c" * 40
        with self.assertRaises(PublishError):
            self.publish()
        self.api.default_head = BASE
        event = copy.deepcopy(EVENT)
        event["workflow_run"]["run_attempt"] = 2
        with self.assertRaises(PublishError):
            self.publisher.publish(RUN_ID, event=event)
        self.assertEqual(self.api.writes, [])

    def test_report_only_advance_uses_current_base_and_original_run_evidence(self):
        publication_base = "c" * 40
        self.api.default_head = publication_base
        same_source = lambda left, right: left == right or (left, right) == (BASE, publication_base)
        self.publisher = Publisher(self.api, REPOSITORY, CASES, same_source=same_source)
        result = self.publisher.publish(RUN_ID, event=EVENT, checkout_sha=publication_base)
        self.assertEqual(result["outcome"], "merged")
        self.assertEqual(self.api.commit_parent, publication_base)
        self.assertEqual(self.api.pull_base, publication_base)
        self.assertIn(BASE, self.api.report)
        self.assertNotIn(publication_base, self.api.report)
        self.assertEqual(self.api.report, render(ROWS, CASES, evidence_prefix(RUN_URL, BASE, 1)))

    def test_source_comparison_rejects_code_advance_without_writes(self):
        self.api.default_head = "d" * 40
        self.publisher = Publisher(self.api, REPOSITORY, CASES,
                                   same_source=lambda left, right: left == right or right == "c" * 40)
        with self.assertRaises(PublishError):
            self.publisher.publish(RUN_ID, event=EVENT, checkout_sha=self.api.default_head)
        self.assertEqual(self.api.writes, [])

    def test_even_equivalent_base_races_fail_before_writes_or_merge(self):
        for stage in ("download", "status"):
            with self.subTest(stage=stage):
                self.api = FakeAPI()
                self.publisher = Publisher(self.api, REPOSITORY, CASES,
                                           same_source=lambda left, right: right in (BASE, "c" * 40))
                if stage == "download":
                    self.api.advance_base_after_download = "c" * 40
                else:
                    self.api.advance_base_after_status = True
                with self.assertRaisesRegex(PublishError, "head changed"):
                    self.publish()
                self.assertFalse(any(call[0].endswith("/merge") for call in self.api.calls))
                if stage == "download":
                    self.assertEqual(self.api.writes, [])

    def test_live_publication_requires_dispatch(self):
        with self.assertRaises(PublishError):
            self.publisher.publish(RUN_ID)
        self.assertEqual(self.api.writes, [])

    def test_live_publication_rejects_a_different_checkout_revision(self):
        with self.assertRaises(PublishError):
            self.publisher.publish(RUN_ID, event=EVENT, checkout_sha="c" * 40)
        self.assertEqual(self.api.writes, [])

    def test_expired_and_oversized_artifacts_are_rejected_before_download(self):
        for expired, size in [(True, 100), (False, MAX_ZIP_BYTES + 1)]:
            with self.subTest(expired=expired):
                self.api.expired, self.api.artifact_size = expired, size
                with self.assertRaises(PublishError):
                    self.publish()
        self.assertFalse(any(call[3] for call in self.api.calls))
        self.assertEqual(self.api.writes, [])

    def test_non_ci_extra_fields_and_wrong_evidence_are_rejected(self):
        for row in [dict(ROWS[0], case_id="E2E-001"), dict(ROWS[0], extra="not allowed"),
                    dict(ROWS[0], evidence="untrusted run"), dict(ROWS[0], status="Unknown")]:
            with self.subTest(row=row):
                self.api.archive = make_zip(json.dumps([row]).encode())
                with self.assertRaises(ValueError):
                    self.publish()
        self.assertEqual(self.api.writes, [])

    def test_empty_artifact_and_unchanged_report_do_not_write(self):
        self.api.archive = make_zip(b"[]")
        self.assertEqual(self.publish()["outcome"], "empty")
        self.api.archive = make_zip()
        self.api.current_report = self.api.report
        self.assertEqual(self.publish()["outcome"], "unchanged")
        self.assertEqual(self.api.writes, [])

    def test_publishes_only_report_and_rebase_merges_bound_head(self):
        result = self.publish()
        self.assertEqual(result["outcome"], "merged")
        tree = next(call[2] for call in self.api.writes if call[0].endswith("git/trees"))
        self.assertEqual([entry["path"] for entry in tree["tree"]], [REPORT_PATH])
        status = next(call[2] for call in self.api.writes if "/statuses/" in call[0])
        self.assertEqual(status["context"], "CI result validation")
        merge = next(call[2] for call in self.api.writes if call[0].endswith("/merge"))
        self.assertEqual(merge, {"merge_method": "rebase", "sha": HEAD})
        self.assertEqual(self.api.writes[-1][1], "DELETE")
        self.assertFalse(self.api.branch_exists)

    def test_report_only_guard_rejects_other_paths_or_content(self):
        self.api.changed_files = [{"filename": "Sources/unsafe.swift", "status": "modified"}]
        with self.assertRaises(PublishError):
            self.publish()
        self.assertFalse(any(call[0].endswith("/merge") for call in self.api.calls))
        self.api = FakeAPI()
        self.publisher = Publisher(self.api, REPOSITORY, CASES)
        self.api.branch_exists = True
        self.api.report = "unexpected report content"
        with self.assertRaises(PublishError):
            self.publish()
        self.assertEqual(self.api.writes, [])

    def test_unexpected_existing_branch_fails_without_overwriting(self):
        self.api.branch_exists = True
        self.api.commit_parent = "c" * 40
        with self.assertRaises(PublishError):
            self.publish()
        self.assertEqual(self.api.writes, [])

    def test_verified_existing_branch_and_pr_recover_without_recreating(self):
        self.api.branch_exists = self.api.pull_exists = True
        self.assertEqual(self.publish()["outcome"], "merged")
        self.assertFalse(any(call[0].endswith(("/git/trees", "/git/commits", "/pulls")) for call in self.api.writes))

    def test_changed_default_base_or_pr_head_prevents_merge(self):
        for attribute in ["advance_base_after_status", "mutate_head_after_status"]:
            with self.subTest(attribute=attribute):
                self.api = FakeAPI()
                self.publisher = Publisher(self.api, REPOSITORY, CASES)
                setattr(self.api, attribute, True)
                with self.assertRaises(PublishError):
                    self.publish()
                self.assertFalse(any(call[0].endswith("/merge") for call in self.api.calls))

    def test_branch_protection_failure_does_not_bypass_or_delete(self):
        self.api.merge_error = APIError("protected branch", 403)
        announced = []
        with self.assertRaises(APIError):
            self.publish(on_pull_request=announced.append)
        self.assertEqual(announced, [f"https://github.com/{REPOSITORY}/pull/9"])
        self.assertTrue(self.api.branch_exists)
        self.assertFalse(any(call[1] == "DELETE" for call in self.api.calls))
        self.assertEqual(sum(call[0].endswith("/merge") for call in self.api.calls), 1)

    def test_unknown_mergeability_is_polled_until_ready(self):
        self.api.mergeable_values = [None, None, True]
        with patch("ci_publish.time.sleep") as sleep:
            self.assertEqual(self.publish()["outcome"], "merged")
        sleep.assert_called_once_with(1)

    def test_false_or_still_unknown_mergeability_never_attempts_merge(self):
        for mergeable, expected_waits in [(False, 0), (None, 3)]:
            with self.subTest(mergeable=mergeable):
                self.api = FakeAPI()
                self.publisher = Publisher(self.api, REPOSITORY, CASES)
                self.api.mergeable = mergeable
                with patch("ci_publish.time.sleep") as sleep:
                    with self.assertRaisesRegex(PublishError, "https://github.com/owner/project/pull/9"):
                        self.publish()
                self.assertEqual(sleep.call_count, expected_waits)
                self.assertFalse(any(call[0].endswith("/merge") for call in self.api.calls))

    def test_reusable_publisher_is_restricted_to_one_allowed_report_path(self):
        with self.assertRaises(PublishError):
            Publisher(self.api, REPOSITORY, CASES, report_path="Sources/App.swift")
        e2e_path = "docs/testing/e2e-test-result.md"
        self.api.report_path = e2e_path
        self.api.changed_files = self.api.pull_files = [{"filename": e2e_path, "status": "modified"}]
        self.publisher = Publisher(self.api, REPOSITORY, CASES, report_path=e2e_path)
        guards = []
        result = self.publisher.publish_report(
            base=BASE, report="An independently validated E2E report\n", default_branch="main",
            branch="codex/e2e-results-123", title="docs: update E2E results", body="Only E2E results.",
            run_url=RUN_URL, guard=lambda: guards.append(True),
            validation_context="E2E result validation", validation_description="E2E freshness validated",
        )
        self.assertEqual(result["outcome"], "merged")
        self.assertEqual(len(guards), 2)
        tree = next(call[2] for call in self.api.writes if call[0].endswith("git/trees"))
        self.assertEqual([entry["path"] for entry in tree["tree"]], [e2e_path])
        status = next(call[2] for call in self.api.writes if "/statuses/" in call[0])
        self.assertEqual(status["context"], "E2E result validation")
        self.assertEqual(status["description"], "E2E freshness validated")
        with self.assertRaises(PublishError):
            self.publisher.report_only([{"filename": REPORT_PATH, "status": "modified"}])


class ArtifactTests(unittest.TestCase):
    def test_valid_archive_round_trips(self):
        self.assertEqual(artifact_rows(make_zip()), ROWS)

    def test_malformed_extra_traversal_symlink_and_oversized_zip_are_rejected(self):
        for archive in [b"not a zip", make_zip(extra=True), make_zip(name="../case-results.json"),
                        make_zip(symlink=True), b"x" * (MAX_ZIP_BYTES + 1),
                        make_zip(b"x" * (MAX_JSON_BYTES + 1))]:
            with self.subTest(size=len(archive)):
                with self.assertRaises(PublishError):
                    artifact_rows(archive)

    def test_invalid_utf8_json_and_duplicate_fields_are_rejected(self):
        for content in [b"\xff", b"{", b'[{"status":"Passed","status":"Failed"}]']:
            with self.subTest(content=content):
                with self.assertRaises(PublishError):
                    artifact_rows(make_zip(content))


class GitHubRunnerTests(unittest.TestCase):
    def test_api_uses_argument_array_json_stdin_and_bounded_output(self):
        calls = []

        def runner(arguments, data=None, limit=None):
            calls.append((arguments, data, limit))
            return b'{"ok":true}'

        api = GitHub(runner)
        body = {"body": "Literal `text` and $(not-a-command)\nsecond line"}
        self.assertEqual(api.request("repos/owner/project/pulls", "POST", body), {"ok": True})
        arguments, data, limit = calls[0]
        self.assertIsInstance(arguments, list)
        self.assertIn("--input", arguments)
        self.assertEqual(json.loads(data), body)
        self.assertEqual(limit, MAX_ZIP_BYTES)
        self.assertNotIn("shell", arguments)


if __name__ == "__main__":
    unittest.main()
