"""Publish a validated, report-only PR from a trusted completed default-branch run."""
import base64
import io
import json
import os
import re
import selectors
import stat
import subprocess
import time
import urllib.parse
import zipfile

from ci_results import REPORT_PATH, catalog, evidence_prefix, render, validate_rows

WORKFLOW_PATH = ".github/workflows/test.yml"
ARTIFACT_NAME = "ci-case-results"
MAX_ZIP_BYTES = 2 * 1024 * 1024
MAX_JSON_BYTES = 1024 * 1024
VALIDATION_CONTEXT = "CI result validation"


class PublishError(ValueError):
    pass


class APIError(RuntimeError):
    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


def bounded_command(arguments, data=None, limit=MAX_ZIP_BYTES):
    """Bound subprocess output and elapsed time; never invoke a shell."""
    process = subprocess.Popen(arguments, stdin=subprocess.PIPE if data else subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env={**os.environ, "GH_PROMPT_DISABLED": "1"})
    output, errors = bytearray(), bytearray()
    deadline = time.monotonic() + 90
    try:
        if data:
            process.stdin.write(data)
            process.stdin.close()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ, (output, limit))
            selector.register(process.stderr, selectors.EVENT_READ, (errors, 65536))
            while selector.get_map():
                if time.monotonic() >= deadline:
                    raise APIError("GitHub API command timed out")
                for key, _ in selector.select(timeout=0.5):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        continue
                    destination, maximum = key.data
                    if len(destination) + len(chunk) > maximum:
                        raise APIError("GitHub API response exceeded its size limit")
                    destination.extend(chunk)
        code = process.wait(timeout=max(0.1, deadline - time.monotonic()))
        if code:
            detail = errors.decode("utf-8", errors="replace").strip()
            match = re.search(r"HTTP (\d{3})", detail)
            raise APIError(detail or "GitHub API request failed", int(match[1]) if match else None)
        return bytes(output)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        for pipe in (process.stdin, process.stdout, process.stderr):
            if pipe is not None:
                pipe.close()


class GitHub:
    def __init__(self, runner=bounded_command):
        self.runner = runner

    def request(self, path, method="GET", payload=None, binary=False):
        arguments = ["gh", "api", "--hostname", "github.com", "--method", method, path,
                     "--header", "Accept: application/vnd.github+json",
                     "--header", "X-GitHub-Api-Version: 2022-11-28"]
        data = None
        if payload is not None:
            arguments.extend(["--input", "-"])
            data = json.dumps(payload).encode("utf-8")
            if len(data) > MAX_JSON_BYTES:
                raise PublishError("GitHub API payload is too large")
        response = self.runner(arguments, data=data, limit=MAX_ZIP_BYTES)
        if binary:
            return response
        return json.loads(response) if response else None


def artifact_rows(archive_bytes):
    """Read exactly one bounded regular JSON member, without extracting files."""
    if len(archive_bytes) > MAX_ZIP_BYTES:
        raise PublishError("Artifact archive is too large")
    try:
        with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
            members = archive.infolist()
            if len(members) != 1 or members[0].filename != "case-results.json":
                raise PublishError("Artifact must contain only case-results.json")
            member = members[0]
            mode = member.external_attr >> 16
            if (member.is_dir() or member.flag_bits & 1 or stat.S_ISLNK(mode)
                    or (stat.S_IFMT(mode) not in (0, stat.S_IFREG))
                    or member.file_size > MAX_JSON_BYTES
                    or member.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)):
                raise PublishError("Unsafe or oversized artifact member")
            with archive.open(member) as stream:
                content = stream.read(MAX_JSON_BYTES + 1)
            if len(content) > MAX_JSON_BYTES:
                raise PublishError("Artifact JSON is too large")
    except (zipfile.BadZipFile, RuntimeError, OSError) as error:
        raise PublishError(f"Invalid artifact archive: {error}") from error

    def unique_keys(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise PublishError(f"Duplicate JSON field: {key}")
            value[key] = item
        return value

    try:
        return json.loads(content.decode("utf-8"), object_pairs_hook=unique_keys)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise PublishError("Artifact is not valid UTF-8 JSON") from error


class Publisher:
    def __init__(self, api, repository, cases=None):
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", repository):
            raise PublishError("GITHUB_REPOSITORY must identify owner/repository")
        self.api = api
        self.repository = repository
        self.endpoint = f"repos/{repository}"
        self.cases = catalog() if cases is None else cases

    def request(self, suffix, method="GET", payload=None, binary=False):
        return self.api.request(f"{self.endpoint}/{suffix}", method, payload, binary)

    def optional(self, suffix):
        try:
            return self.request(suffix)
        except APIError as error:
            if error.status == 404:
                return None
            raise

    def branch_head(self, branch):
        return self.request("git/ref/heads/" + urllib.parse.quote(branch, safe="/"))["object"]["sha"]

    def trust_run(self, run_id, branch, event):
        run = self.request(f"actions/runs/{run_id}")
        sha, attempt = run.get("head_sha", ""), run.get("run_attempt")
        if (run.get("id") != run_id or run.get("event") != "push" or run.get("status") != "completed"
                or run.get("name") != "macOS" or run.get("head_branch") != branch
                or run.get("path", "").split("@", 1)[0] != WORKFLOW_PATH
                or run.get("repository", {}).get("full_name") != self.repository
                or run.get("head_repository", {}).get("full_name") != self.repository
                or type(attempt) is not int or attempt < 1
                or type(run.get("workflow_id")) is not int or run["workflow_id"] < 1
                or not re.fullmatch(r"[a-f0-9]{40}", sha)):
            raise PublishError("Run is not a trusted completed default-branch macOS push")
        workflow = self.request(f"actions/workflows/{run['workflow_id']}")
        if workflow.get("path") != WORKFLOW_PATH or workflow.get("name") != "macOS":
            raise PublishError("Run does not belong to the expected workflow")
        if event is not None:
            dispatched = event.get("workflow_run", {})
            if (event.get("action") != "completed"
                    or event.get("repository", {}).get("full_name") != self.repository
                    or dispatched.get("id") != run_id or dispatched.get("run_attempt") != attempt
                    or dispatched.get("head_sha") != sha):
                raise PublishError("Dispatch does not match the current completed run attempt")
        if self.branch_head(branch) != sha:
            raise PublishError("The tested commit is no longer the default-branch head")
        return run

    def read_report(self, ref):
        item = self.optional(f"contents/{REPORT_PATH}?ref={urllib.parse.quote(ref, safe='')}")
        if item is None:
            return None
        if (item.get("type") != "file" or item.get("encoding") != "base64"
                or item.get("size", MAX_JSON_BYTES + 1) > MAX_JSON_BYTES):
            raise PublishError("Unexpected report object")
        try:
            content = base64.b64decode("".join(item["content"].split()), validate=True)
            if len(content) > MAX_JSON_BYTES:
                raise PublishError("Report content is too large")
            return content.decode("utf-8")
        except (KeyError, ValueError, UnicodeError) as error:
            raise PublishError("Invalid report content") from error

    @staticmethod
    def report_only(files):
        if (not isinstance(files, list) or len(files) != 1
                or files[0].get("filename") != REPORT_PATH
                or files[0].get("status") not in ("added", "modified")):
            raise PublishError("Refusing a change outside the single report file")

    def verify_commit(self, base, head, report):
        commit = self.request(f"git/commits/{head}")
        if [parent.get("sha") for parent in commit.get("parents", [])] != [base]:
            raise PublishError("Report branch must contain exactly one commit on the tested base")
        comparison = self.request(f"compare/{base}...{head}")
        if comparison.get("ahead_by") != 1 or comparison.get("behind_by") != 0:
            raise PublishError("Report branch diverged from the tested base")
        self.report_only(comparison.get("files"))
        if self.read_report(head) != report:
            raise PublishError("Report branch content differs from validated results")

    def verify_pull(self, number, branch, base, head, report, default_branch):
        pull = self.request(f"pulls/{number}")
        if (pull.get("state") != "open" or pull.get("draft")
                or pull.get("base", {}).get("ref") != default_branch
                or pull.get("base", {}).get("sha") != base
                or pull.get("base", {}).get("repo", {}).get("full_name") != self.repository
                or pull.get("head", {}).get("ref") != branch
                or pull.get("head", {}).get("sha") != head
                or pull.get("head", {}).get("repo", {}).get("full_name") != self.repository):
            raise PublishError("Pull request base, head, repository, or state changed")
        self.report_only(self.request(f"pulls/{number}/files?per_page=100"))
        self.verify_commit(base, head, report)
        return pull

    def wait_for_mergeable(self, number, head, pull):
        """Allow GitHub three short intervals to calculate a new PR's mergeability."""
        url = f"https://github.com/{self.repository}/pull/{number}"
        for attempt in range(4):
            if pull.get("state") != "open" or pull.get("head", {}).get("sha") != head:
                raise PublishError(f"Pull request changed while checking mergeability: {url}")
            if pull.get("mergeable") is True:
                return
            if pull.get("mergeable") is False:
                raise PublishError(f"Pull request is not mergeable: {url}")
            if attempt == 3:
                raise PublishError(f"GitHub has not finished calculating mergeability: {url}")
            time.sleep(1)
            pull = self.request(f"pulls/{number}")

    def publish(self, run_id, dry_run=False, event=None, checkout_sha=None, on_pull_request=None):
        if type(run_id) is not int or run_id < 1:
            raise PublishError("Expected a positive workflow run ID")
        if not dry_run and event is None:
            raise PublishError("Live publishing requires the workflow_run event payload")
        repository = self.api.request(self.endpoint)
        if repository.get("full_name") != self.repository:
            raise PublishError("Repository identity mismatch")
        default_branch = repository["default_branch"]
        run = self.trust_run(run_id, default_branch, event)
        base, attempt = run["head_sha"], run["run_attempt"]
        if not dry_run and checkout_sha != base:
            raise PublishError("Trusted checkout and tested default-branch revision differ")
        run_url = f"https://github.com/{self.repository}/actions/runs/{run_id}"
        prefix = evidence_prefix(run_url, base, attempt)
        listing = self.request(f"actions/runs/{run_id}/artifacts?per_page=100")
        if listing.get("total_count", 101) > 100:
            raise PublishError("Too many artifacts to validate unambiguously")
        matches = [item for item in listing.get("artifacts", []) if item.get("name") == ARTIFACT_NAME]
        if len(matches) != 1:
            raise PublishError("Expected exactly one ci-case-results artifact")
        artifact = matches[0]
        if (artifact.get("expired") is not False or type(artifact.get("id")) is not int
                or type(artifact.get("size_in_bytes")) is not int
                or not 0 < artifact["size_in_bytes"] <= MAX_ZIP_BYTES):
            raise PublishError("Artifact is expired or exceeds its size limit")
        rows = validate_rows(artifact_rows(self.request(f"actions/artifacts/{artifact['id']}/zip", binary=True)), self.cases, prefix)
        if not rows:
            return {"outcome": "empty", "run_id": run_id}
        report = render(rows, self.cases, prefix)
        if self.read_report(base) == report:
            return {"outcome": "unchanged", "run_id": run_id}
        if dry_run:
            return {"outcome": "dry-run", "run_id": run_id, "case_count": len(rows), "report": report}

        # Recheck before creating any objects; a rerun or newer main commit invalidates this work.
        current = self.trust_run(run_id, default_branch, event)
        if current["run_attempt"] != attempt or current["head_sha"] != base:
            raise PublishError("Run changed before publication")
        branch = f"codex/ci-results-{run_id}-{attempt}"
        ref_path = f"git/ref/heads/{branch}"
        existing = self.optional(ref_path)
        if existing is not None:
            head = existing["object"]["sha"]
            self.verify_commit(base, head, report)
        else:
            original = self.request(f"git/commits/{base}")
            tree = self.request("git/trees", "POST", {
                "base_tree": original["tree"]["sha"],
                "tree": [{"path": REPORT_PATH, "mode": "100644", "type": "blob", "content": report}],
            })
            commit = self.request("git/commits", "POST", {
                "message": f"docs: update CI test results for run {run_id} attempt {attempt}",
                "tree": tree["sha"], "parents": [base],
            })
            head = commit["sha"]
            self.request("git/refs", "POST", {"ref": f"refs/heads/{branch}", "sha": head})
            self.verify_commit(base, head, report)

        owner = self.repository.split("/", 1)[0]
        query = urllib.parse.urlencode({"state": "all", "head": f"{owner}:{branch}", "base": default_branch, "per_page": 100})
        pulls = self.request(f"pulls?{query}")
        if pulls:
            if len(pulls) != 1 or pulls[0].get("state") != "open":
                raise PublishError("Unexpected existing pull request for the report branch")
            number = pulls[0]["number"]
        else:
            pull = self.request("pulls", "POST", {
                "title": f"docs: update CI test results (run {run_id}, attempt {attempt})",
                "head": branch, "base": default_branch,
                "body": f"Update only `{REPORT_PATH}` from [{base}]({run_url}/attempts/{attempt}).\n\n"
                        f"The publisher validated the completed default-branch run, {len(rows)} CI case results, "
                        "canonical evidence, and the report-only diff. Merge method: rebase.\n",
            })
            number = pull["number"]
        pull_url = f"https://github.com/{self.repository}/pull/{number}"
        if on_pull_request is not None:
            on_pull_request(pull_url)
        self.verify_pull(number, branch, base, head, report, default_branch)
        self.request(f"statuses/{head}", "POST", {
            "state": "success", "context": VALIDATION_CONTEXT,
            "description": "Trusted CI results and report-only change validated",
            "target_url": run_url,
        })
        pull = self.verify_pull(number, branch, base, head, report, default_branch)
        self.wait_for_mergeable(number, head, pull)
        self.trust_run(run_id, default_branch, event)
        # The expected head SHA prevents a concurrent branch update from being merged.
        merged = self.request(f"pulls/{number}/merge", "PUT", {"merge_method": "rebase", "sha": head})
        if merged.get("merged") is not True:
            raise PublishError("GitHub did not merge the report PR; repository rules remain in force")
        remaining = self.optional(ref_path)
        if remaining is not None:
            if remaining["object"]["sha"] != head:
                raise PublishError("Merged branch changed; refusing to delete it")
            try:
                self.request(f"git/refs/heads/{branch}", "DELETE")
            except APIError as error:
                if error.status != 404:
                    raise
        return {"outcome": "merged", "run_id": run_id, "pull_request": pull_url}
