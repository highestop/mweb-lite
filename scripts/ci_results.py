"""Collect and render CI case results without modifying case definitions."""
import importlib.util
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("case_checker", ROOT / "scripts/check-test-cases.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
STATUSES = {"Passed", "Failed", "Skipped"}
REPORT_PATH = "docs/testing/ci-test-result.md"


def catalog(root=ROOT):
    return {identifier: fields for identifier, fields, _ in
            (checker.read_case(path) for path in sorted((root / "docs/testing/cases").glob("*.md")))}


def evidence_prefix(run_url, source_sha, attempt):
    if not re.fullmatch(r"https://github\.com/[\w.-]+/[\w.-]+/actions/runs/[1-9][0-9]*", run_url):
        raise ValueError("Expected a GitHub Actions run URL")
    if not re.fullmatch(r"[a-f0-9]{40}", source_sha) or attempt < 1:
        raise ValueError("Expected the full tested commit SHA and a positive run attempt")
    return f"[{source_sha}]({run_url}/attempts/{attempt})"


def validate_record(row):
    if not isinstance(row, dict) or set(row) != {"case_id", "status", "evidence"}:
        raise ValueError("Each result must contain only case_id, status, and evidence")
    if not isinstance(row["case_id"], str):
        raise ValueError("Expected a string case ID")
    if not isinstance(row["status"], str) or row["status"] not in STATUSES:
        raise ValueError(f"Invalid result for {row['case_id']}")
    evidence = row["evidence"]
    if not isinstance(evidence, str) or not evidence.strip() or len(evidence) > 4000:
        raise ValueError(f"Invalid evidence for {row['case_id']}")
    if any(ord(c) < 32 or ord(c) == 127 for c in evidence):
        raise ValueError(f"Evidence must be one line: {row['case_id']}")


def validate_rows(rows, cases, prefix=None):
    if not isinstance(rows, list) or len(rows) > len(cases):
        raise ValueError("Expected a JSON array of case results")
    seen = set()
    for row in rows:
        validate_record(row)
        identifier = row["case_id"]
        if identifier not in cases or cases[identifier]["Path"] != "CI":
            raise ValueError(f"Unknown or non-CI case: {identifier!r}")
        if identifier in seen:
            raise ValueError(f"Duplicate result: {identifier}")
        if prefix is not None and not row["evidence"].startswith(prefix + " — "):
            raise ValueError(f"Evidence does not match the trusted run and source: {identifier}")
        seen.add(identifier)
    return sorted(rows, key=lambda row: row["case_id"])


def collect(xctest, preview, cases, prefix, require_xctest=False, require_preview=False):
    results = []
    selectors = {}
    for identifier, fields in cases.items():
        for selector in re.findall(r"\b(\w+Tests/test\w+)\b", fields["Verification"]):
            selectors[selector] = identifier
    expected_xctest = {identifier for identifier in selectors.values() if cases[identifier]["Path"] == "CI"}
    expected_preview = {identifier for identifier, fields in cases.items()
                        if identifier.startswith("PV-") and fields["Path"] == "CI"}
    for path, kind, required, expected in ((xctest, "XCTest", require_xctest, expected_xctest),
                                            (preview, "preview", require_preview, expected_preview)):
        observed = set()
        if path.exists():
            for line in path.read_text().splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                validate_record(row)
                identifier = row["case_id"]
                if identifier not in cases:
                    raise ValueError(f"Result has no case definition: {identifier}")
                if kind == "XCTest":
                    selector = row["evidence"].split(":", 1)[0]
                    if selectors.get(selector) != identifier:
                        raise ValueError(f"XCTest selector does not match its case: {selector}")
                elif not re.fullmatch(r"PV-\d{3}", identifier):
                    raise ValueError("Unexpected preview case ID")
                if identifier in observed:
                    raise ValueError(f"Duplicate result: {identifier}")
                observed.add(identifier)
                # Optional local-only cases never enter the CI artifact.
                if cases[identifier]["Path"] == "CI":
                    results.append(dict(row, evidence=prefix + " — " + row["evidence"][:2000]))
        if required and not expected.issubset(observed):
            raise ValueError(f"Successful {kind} runner omitted cases: {sorted(expected - observed)}")
    return validate_rows(results, cases, prefix)


def render(rows, cases, prefix):
    rows = validate_rows(rows, cases, prefix)
    match = re.fullmatch(
        r"\[([a-f0-9]{40})\]\((https://github\.com/[\w.-]+/[\w.-]+)/actions/runs/([1-9][0-9]*)/attempts/([1-9][0-9]*)\)",
        prefix,
    )
    if match is None:
        raise ValueError("Expected a canonical shared CI run and tested revision")
    sha, repository_url, run_id, attempt = match.groups()
    run_url = f"{repository_url}/actions/runs/{run_id}/attempts/{attempt}"
    lines = [
        "# CI test result", "",
        f"CI run: [{run_id} (attempt {attempt})]({run_url})",
        f"Tested commit: [{sha}]({repository_url}/commit/{sha})", "",
        "| Case ID | Status |", "| --- | --- |",
    ]
    for row in rows:
        identifier = row["case_id"]
        lines.append(f"| [{identifier}](cases/{identifier}.md) | {row['status']} |")
    return "\n".join(lines) + "\n"
