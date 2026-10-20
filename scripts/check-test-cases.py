#!/usr/bin/env python3
"""Check the GWT catalog, XCTest mappings, fixture references, and result evidence."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "docs/testing/test-cases.md"
LEVELS = {"Unit", "Integration", "End-to-end"}
PASSED_BY_PATH = {"CI": "CI passed", "Local script": "Local script passed",
                  "Preview app": "Preview app passed", "Release app": "Release app passed"}
STATUSES = {"Pending", "Failed", "Blocked", "Skipped", *PASSED_BY_PATH.values()}


def check():
    text = CATALOG.read_text()
    cases = {}
    selectors = []
    in_case_table = False
    for number, line in enumerate(text.splitlines(), 1):
        if line == "| ID | Given | When | Then | Level | Path | Data | Status | Verification | Evidence |":
            in_case_table = True
            continue
        if not line.startswith("|"):
            in_case_table = False
        if not in_case_table and re.match(r"\| [A-Z][A-Z0-9]*-\d{3} \|", line):
            raise ValueError(f"Line {number}: case row must belong to a table with the standard header")
        if not in_case_table or re.fullmatch(r"[| :\-]+", line):
            continue
        fields = [value.strip() for value in re.split(r"(?<!\\)\|", line.strip().strip("|"))]
        if len(fields) != 10:
            raise ValueError(f"Line {number}: expected ten table columns")
        identifier, given, when, then, level, path, data, status, verification, evidence = fields
        if not re.fullmatch(r"[A-Z][A-Z0-9]*-\d{3}", identifier):
            raise ValueError(f"Line {number}: invalid case ID {identifier!r}")
        if identifier in cases:
            raise ValueError(f"Duplicate case ID: {identifier}")
        if not all((given, when, then, verification)) or level not in LEVELS or path not in PASSED_BY_PATH or status not in STATUSES:
            raise ValueError(f"{identifier}: incomplete GWT/verification or invalid level/path/status")
        if status.endswith(" passed") and status != PASSED_BY_PATH[path]:
            raise ValueError(f"{identifier}: pass status must match the actual verification path")
        if data != "Inline" and not data.startswith(("Fixture:", "Mixed:")):
            raise ValueError(f"{identifier}: data must be Inline, Fixture: <link>, or Mixed: <link> plus generated inputs")
        if data != "Inline":
            targets = re.findall(r"\[[^]]+\]\(([^)]+)\)", data)
            fixture_root = (ROOT / "Tests/Fixtures").resolve()
            if not targets or any(not (CATALOG.parent / target).resolve().is_relative_to(fixture_root) for target in targets):
                raise ValueError(f"{identifier}: fixture data must link to its source under Tests/Fixtures")
        if status != "Pending" and not re.search(r"\[[^]]+\]\([^)]+\)", evidence):
            raise ValueError(f"{identifier}: recorded results require a linked evidence record")
        selectors.extend(re.findall(r"\b(\w+Tests/test\w+)\b", verification))
        cases[identifier] = fields
    if not cases:
        raise ValueError("No test cases found")

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
    catalog_preview = {identifier for identifier in cases if identifier.startswith("PV-")}
    if emitted != catalog_preview:
        raise ValueError("Preview harness IDs do not match catalog cases")
    for target in re.findall(r"\[[^]]+\]\(([^)]+)\)", text):
        if "://" not in target and not target.startswith("#"):
            if not (CATALOG.parent / target.split("#", 1)[0]).exists():
                raise ValueError(f"Missing catalog link target: {target}")
    for fixture in re.findall(r"`((?:Preview|Library)/[^`]+)`", text):
        if not (ROOT / "Tests/Fixtures" / fixture).exists():
            raise ValueError(f"Missing fixture: {fixture}")
    for path in (ROOT / "Tests/Fixtures").rglob("*"):
        if path.suffix.lower() in {".db", ".sqlite", ".sqlite3", ".app", ".zip"}:
            raise ValueError(f"Generated data does not belong in source fixtures: {path}")
    print(f"PASS: {len(cases)} GWT cases, {len(actual)} XCTest mappings, {len(emitted)} preview cases; fixture and evidence references resolve")


if __name__ == "__main__":
    try:
        check()
    except (ValueError, OSError) as error:
        sys.exit(str(error))
