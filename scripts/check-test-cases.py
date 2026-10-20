#!/usr/bin/env python3
"""Check individual GWT cases, their index, XCTest mappings, and result references."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
INDEX = ROOT / "docs/testing/test-cases.md"
CASE_DIR = INDEX.parent / "cases"
FIELDS = ["Given", "When", "Then", "Level", "Path", "Data", "Status", "Verification", "Evidence"]
LEVELS = {"Unit", "Integration", "End-to-end"}
PASSED_BY_PATH = {"CI": "CI passed", "Local script": "Local script passed",
                  "Preview app": "Preview app passed", "Release app": "Release app passed"}
STATUSES = {"—", "Failed", "Blocked", "Skipped", *PASSED_BY_PATH.values()}


def links(text):
    return re.findall(r"\[[^]]+\]\(([^)]+)\)", text)


def local_run_artifact(target, source):
    """Local evidence is ignored and intentionally absent from a clean checkout."""
    if "://" in target or target.startswith("#"):
        return False
    path = (source.parent / target.split("#", 1)[0]).resolve()
    return any(path.is_relative_to((ROOT / folder).resolve())
               for folder in ("build/test-results", "build/Test Runs"))


def read_case(source):
    identifier = source.stem
    if not re.fullmatch(r"[A-Z][A-Z0-9]*-\d{3}", identifier):
        raise ValueError(f"Invalid case filename: {source.name}")
    text = source.read_text()
    headings = list(re.finditer(r"^## (.+)$", text, re.MULTILINE))
    if [heading[1] for heading in headings] != FIELDS:
        raise ValueError(f"{identifier}: expected exactly these ordered fields: {', '.join(FIELDS)}")
    if text[:headings[0].start()].strip() != f"# {identifier}":
        raise ValueError(f"{identifier}: title must match the case filename")
    values = {heading[1]: text[heading.end():headings[i + 1].start() if i + 1 < len(headings) else len(text)].strip()
              for i, heading in enumerate(headings)}
    if not all(values.values()):
        raise ValueError(f"{identifier}: all fields need content; use — only for an unrecorded result")
    return identifier, values, text


def check():
    cases = {}
    selectors = []
    sources = {INDEX: INDEX.read_text()}
    for source in sorted(CASE_DIR.glob("*.md")):
        identifier, fields, text = read_case(source)
        level, path, data, status, evidence = (fields[name] for name in ("Level", "Path", "Data", "Status", "Evidence"))
        if level not in LEVELS or path not in PASSED_BY_PATH or status not in STATUSES:
            raise ValueError(f"{identifier}: invalid level/path/status")
        if status.endswith(" passed") and status != PASSED_BY_PATH[path]:
            raise ValueError(f"{identifier}: pass status must match the actual verification path")
        if data != "Inline" and not data.startswith(("Fixture:", "Mixed:")):
            raise ValueError(f"{identifier}: data must be Inline, Fixture: <link>, or Mixed: <link> plus generated inputs")
        if data != "Inline":
            targets = links(data)
            fixture_root = (ROOT / "Tests/Fixtures").resolve()
            if not targets or any(not (source.parent / target).resolve().is_relative_to(fixture_root) for target in targets):
                raise ValueError(f"{identifier}: fixture data must link to its source under Tests/Fixtures")
        if status == "—" and evidence != "—":
            raise ValueError(f"{identifier}: a case without an execution result must have no evidence")
        evidence_targets = links(evidence)
        if status != "—" and not evidence_targets:
            raise ValueError(f"{identifier}: recorded results require a linked CI run or local-only artifact")
        for target in evidence_targets:
            if local_run_artifact(target, source):
                if "local-only" not in evidence.lower():
                    raise ValueError(f"{identifier}: ignored local evidence must be labeled local-only")
            elif not target.startswith(("https://", "http://")):
                raise ValueError(f"{identifier}: run reports must be external or in ignored build output")
        selectors.extend(re.findall(r"\b(\w+Tests/test\w+)\b", fields["Verification"]))
        cases[identifier] = fields
        sources[source] = text
    if not cases:
        raise ValueError("No test case files found")
    indexed = re.findall(r"\[[^]]+\]\(cases/([A-Z][A-Z0-9]*-\d{3})\.md\)", sources[INDEX])
    if len(indexed) != len(set(indexed)) or set(indexed) != set(cases):
        raise ValueError("The index must link to every case file exactly once")

    actual = set()
    for folder in ("MWebCoreTests", "MWebLiteTests"):
        for path in (ROOT / "Tests" / folder).glob("*.swift"):
            source = path.read_text()
            classes = re.findall(r"class (\w+Tests): XCTestCase", source)
            if len(classes) != 1:
                raise ValueError(f"Expected one XCTestCase class in {path.name}")
            actual.update(f"{classes[0]}/{name}" for name in re.findall(r"func (test\w+)\(", source))
    if len(selectors) != len(set(selectors)):
        raise ValueError("An XCTest selector is mapped more than once")
    if set(selectors) != actual:
        raise ValueError(f"XCTest mapping mismatch; missing={sorted(actual-set(selectors))}, stale={sorted(set(selectors)-actual)}")
    preview_source = (ROOT / "Tests/PreviewIntegration/main.swift").read_text()
    emitted = set(re.findall(r"PASS (PV-\d{3})", preview_source))
    if emitted != {identifier for identifier in cases if identifier.startswith("PV-")}:
        raise ValueError("Preview harness IDs do not match case files")

    for source, text in sources.items():
        for target in links(text):
            if "://" not in target and not target.startswith("#") and not local_run_artifact(target, source):
                if not (source.parent / target.split("#", 1)[0]).exists():
                    raise ValueError(f"Missing link target in {source.name}: {target}")
        for fixture in re.findall(r"`((?:Preview|Library)/[^`]+)`", text):
            if not (ROOT / "Tests/Fixtures" / fixture).exists():
                raise ValueError(f"Missing fixture in {source.name}: {fixture}")
    for path in (ROOT / "Tests/Fixtures").rglob("*"):
        if path.suffix.lower() in {".db", ".sqlite", ".sqlite3", ".app", ".zip"}:
            raise ValueError(f"Generated data does not belong in source fixtures: {path}")
    print(f"PASS: {len(cases)} GWT case files, {len(actual)} XCTest mappings, {len(emitted)} preview cases; index, fixture links, and result references are valid")


if __name__ == "__main__":
    try:
        check()
    except (ValueError, OSError) as error:
        sys.exit(str(error))
