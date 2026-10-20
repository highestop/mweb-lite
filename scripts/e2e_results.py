"""Read manual E2E results and compare their recorded revisions with Git history."""
import os
import re
import subprocess

REPORT_PATH = "docs/testing/e2e-test-result.md"
RESULT_PATHS = frozenset({"docs/testing/ci-test-result.md", REPORT_PATH})
STATUSES = {"Passed", "Failed", "Skipped"}
FIELDS = {"case_id", "status", "commit_sha", "outdated"}
TITLE = "# E2E test result"
HEADER = "| Case ID | Status | Commit SHA | Outdated |"
SEPARATOR = "| --- | --- | --- | --- |"
SHA_PATTERN = r"[a-f0-9]{40}"


class HistoryError(ValueError):
    """A commit comparison cannot be established from the available Git history."""


def validate_record(row):
    if not isinstance(row, dict) or set(row) != FIELDS:
        raise ValueError("An E2E result must contain case_id, status, commit_sha, and outdated")
    identifier = row["case_id"]
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Z][A-Z0-9]*-\d{3}", identifier):
        raise ValueError("Invalid E2E result case ID")
    if not all(isinstance(row[field], str) for field in FIELDS):
        raise ValueError(f"{identifier}: result values must be strings")
    if row["status"] == "—":
        if row["commit_sha"] != "—" or row["outdated"] != "—":
            raise ValueError(f"{identifier}: an unrecorded result must use — in all three result columns")
    elif (row["status"] not in STATUSES or not re.fullmatch(SHA_PATTERN, row["commit_sha"])
          or row["outdated"] not in {"", "Yes"}):
        raise ValueError(f"{identifier}: expected a result, full tested commit SHA, and blank/Yes outdated flag")


def validate_rows(rows, cases):
    if not isinstance(rows, list):
        raise ValueError("Expected a list of E2E results")
    expected = {identifier for identifier, fields in cases.items() if fields["Level"] == "End-to-end"}
    seen = set()
    for row in rows:
        validate_record(row)
        identifier = row["case_id"]
        if identifier not in expected:
            raise ValueError(f"Unknown or non-end-to-end case: {identifier}")
        if identifier in seen:
            raise ValueError(f"Duplicate E2E result: {identifier}")
        seen.add(identifier)
    if seen != expected:
        raise ValueError(f"E2E result table must cover every end-to-end case; missing={sorted(expected - seen)}")
    return sorted(rows, key=lambda row: row["case_id"])


def read_rows(text, cases):
    lines = text.strip().splitlines()
    if lines[:4] != [TITLE, "", HEADER, SEPARATOR]:
        raise ValueError("Expected the E2E test result title and four-column table")
    rows = []
    for number, line in enumerate(lines[4:], 5):
        if not line.startswith("| ") or not line.endswith(" |"):
            raise ValueError(f"Line {number}: expected one E2E result table row")
        fields = [value.strip() for value in line[1:-1].split("|")]
        if len(fields) != 4:
            raise ValueError(f"Line {number}: expected four columns")
        identifier, status, commit, outdated = fields
        match = re.fullmatch(r"\[([A-Z][A-Z0-9]*-\d{3})\]\(cases/\1\.md\)", identifier)
        if match is None:
            raise ValueError(f"Line {number}: case ID must link to its own definition")
        if commit != "—":
            if not re.fullmatch(r"`" + SHA_PATTERN + r"`", commit):
                raise ValueError(f"Line {number}: tested commit must be a full SHA in backticks")
            commit = commit[1:-1]
        rows.append({"case_id": match[1], "status": status, "commit_sha": commit, "outdated": outdated})
    return validate_rows(rows, cases)


def render(rows, cases):
    lines = [TITLE, "", HEADER, SEPARATOR]
    for row in validate_rows(rows, cases):
        identifier = row["case_id"]
        commit = "—" if row["commit_sha"] == "—" else f"`{row['commit_sha']}`"
        lines.append(f"| [{identifier}](cases/{identifier}.md) | {row['status']} | {commit} | {row['outdated']} |")
    return "\n".join(lines) + "\n"


def _git(repo, *arguments):
    environment = dict(os.environ, GIT_OPTIONAL_LOCKS="0", GIT_NO_LAZY_FETCH="1", GIT_NO_REPLACE_OBJECTS="1")
    try:
        result = subprocess.run(["git", "-C", str(repo), *arguments], capture_output=True,
                                check=False, timeout=20, env=environment)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise HistoryError(f"Could not read Git history: {error}") from error
    if result.returncode:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise HistoryError(f"Could not read Git history; fetch the required commits: {detail}")
    return result.stdout


def resolve_commit(repo, ref):
    if not isinstance(ref, str) or not ref:
        raise HistoryError("Expected a commit or Git ref")
    commit = _git(repo, "rev-parse", "--verify", "--end-of-options", ref + "^{commit}").decode().strip()
    if not re.fullmatch(SHA_PATTERN, commit):
        raise HistoryError("Git did not resolve a full commit SHA")
    return commit


def effective_commit(repo, ref):
    """Ignore only nonempty report-only commits, following each first parent."""
    if _git(repo, "rev-parse", "--is-shallow-repository").strip() == b"true":
        raise HistoryError("E2E freshness requires full Git history; fetch with --unshallow first")
    commit = resolve_commit(repo, ref)
    while True:
        parents = _git(repo, "rev-list", "--parents", "--max-count=1", commit).decode().split()[1:]
        if not parents:
            return commit
        first_parent = parents[0]
        changed = set(_git(repo, "diff-tree", "--no-commit-id", "--name-only", "--no-renames",
                           "-r", "-z", first_parent, commit, "--").split(b"\0")) - {b""}
        if not changed or not changed.issubset(path.encode("utf-8") for path in RESULT_PATHS):
            return commit
        commit = first_parent


def refresh(rows, repo, head):
    """Recompute only outdated flags; this does not run tests or inspect dirty files."""
    current = effective_commit(repo, head)
    cache = {}
    refreshed = []
    seen = set()
    for row in rows:
        validate_record(row)
        if row["case_id"] in seen:
            raise ValueError(f"Duplicate E2E result: {row['case_id']}")
        seen.add(row["case_id"])
        updated = dict(row)
        tested = row["commit_sha"]
        if tested != "—":
            if tested not in cache:
                try:
                    cache[tested] = effective_commit(repo, tested)
                except HistoryError:
                    # Missing tested history cannot establish that an old result is current.
                    cache[tested] = None
            updated["outdated"] = "" if cache[tested] == current else "Yes"
        refreshed.append(updated)
    return refreshed
