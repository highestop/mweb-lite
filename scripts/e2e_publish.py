"""Publish freshness flags without changing any manual E2E execution result."""
import pathlib
import re
import subprocess

from ci_publish import Publisher, PublishError
from ci_results import catalog
from e2e_results import REPORT_PATH, effective_commit, read_rows, refresh, render

CI_PUBLISH_WORKFLOW = ".github/workflows/publish-ci-test-results.yml"
CI_PUBLISH_NAME = "Publish CI test results"


def checkout_revision(repo):
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()


class E2EPublisher:
    def __init__(self, api, repository, repo, cases=None):
        self.repo = pathlib.Path(repo)
        self.cases = catalog(self.repo) if cases is None else cases
        self.writer = Publisher(api, repository, self.cases, report_path=REPORT_PATH)
        self.repository = repository

    def source_matches(self, source, base):
        if not isinstance(source, str) or not re.fullmatch(r"[a-f0-9]{40}", source):
            raise PublishError("Event does not identify a full source commit")
        return effective_commit(self.repo, source) == effective_commit(self.repo, base)

    def eligible(self, event_name, event, default_branch, base, workflow_ref):
        if event.get("repository", {}).get("full_name") != self.repository:
            raise PublishError("Event repository does not match the checkout")
        if event_name == "push":
            if event.get("ref") != f"refs/heads/{default_branch}" or event.get("deleted"):
                raise PublishError("Only default-branch pushes can update E2E freshness")
            after, before = event.get("after"), event.get("before")
            if not self.source_matches(after, base):
                return "stale"
            # A source-changing push waits for the CI publisher to finish. Publishing
            # a freshness commit first must not race publication of that CI run.
            if not isinstance(before, str) or not re.fullmatch(r"[a-f0-9]{40}", before):
                raise PublishError("Push does not identify its previous commit")
            if before == "0" * 40:
                return "deferred"
            try:
                report_only = self.source_matches(before, after)
            except ValueError:
                return "deferred"
            return "ready" if report_only else "deferred"
        if event_name == "workflow_run":
            dispatched = event.get("workflow_run", {})
            run_id = dispatched.get("id")
            if event.get("action") != "completed" or type(run_id) is not int or run_id < 1:
                raise PublishError("Expected a completed CI publisher dispatch")
            run = self.writer.request(f"actions/runs/{run_id}")
            if (run.get("id") != run_id or run.get("status") != "completed"
                    or run.get("event") != "workflow_run" or run.get("name") != CI_PUBLISH_NAME
                    or run.get("path", "").split("@", 1)[0] != CI_PUBLISH_WORKFLOW
                    or run.get("head_branch") != default_branch
                    or run.get("repository", {}).get("full_name") != self.repository
                    or run.get("head_repository", {}).get("full_name") != self.repository
                    or type(run.get("run_attempt")) is not int or run["run_attempt"] < 1
                    or dispatched.get("run_attempt") != run["run_attempt"]
                    or dispatched.get("head_sha") != run.get("head_sha")):
                raise PublishError("Untrusted CI publisher completion")
            if run.get("conclusion") == "skipped":
                return "deferred"
            return "ready" if self.source_matches(run["head_sha"], base) else "stale"
        if event_name == "workflow_dispatch":
            if workflow_ref != f"refs/heads/{default_branch}":
                raise PublishError("Manual refresh must use the default branch")
            return "ready"
        raise PublishError("Unsupported E2E freshness trigger")

    def publish(self, event_name, event, workflow_ref, workflow_run_id, dry_run=False, on_pull_request=None):
        if type(workflow_run_id) is not int or workflow_run_id < 1:
            raise PublishError("Expected the current workflow run ID")
        metadata = self.writer.api.request(self.writer.endpoint)
        if metadata.get("full_name") != self.repository:
            raise PublishError("Repository identity mismatch")
        default_branch = metadata["default_branch"]
        base = self.writer.branch_head(default_branch)
        if checkout_revision(self.repo) != base:
            raise PublishError("Checkout is not the current default-branch head")
        outcome = self.eligible(event_name, event, default_branch, base, workflow_ref)
        if outcome != "ready":
            return {"outcome": outcome}
        text = self.writer.read_report(base)
        if text is None:
            raise PublishError("The E2E result table is missing")
        rows = read_rows(text, self.cases)
        updated = refresh(rows, self.repo, base)
        manual_fields = lambda items: [(row["case_id"], row["status"], row["commit_sha"]) for row in items]
        if manual_fields(rows) != manual_fields(updated):
            raise PublishError("Freshness calculation changed a manual result")
        if updated == rows:
            return {"outcome": "unchanged"}
        report = render(updated, self.cases)
        if dry_run:
            return {"outcome": "dry-run", "report": report}

        def guard():
            if self.writer.branch_head(default_branch) != base:
                raise PublishError("Default branch advanced; preserving newer manual results")

        run_url = f"https://github.com/{self.repository}/actions/runs/{workflow_run_id}"
        return self.writer.publish_report(
            base=base, report=report, default_branch=default_branch,
            branch=f"codex/e2e-results-{base}",
            title="docs: update E2E result freshness",
            body=f"Update only Outdated flags in `{REPORT_PATH}` against `{base}`.\n\n"
                 "Execution statuses and tested commit SHAs are preserved. Commits that change only "
                 "the two result tables are ignored when comparing versions.\n\n"
                 f"[Freshness workflow]({run_url}). Merge method: rebase; delete the report branch afterward.\n",
            run_url=run_url, guard=guard, on_pull_request=on_pull_request,
            validation_context="E2E result validation",
            validation_description="Only E2E freshness flags changed; manual results preserved",
        )
