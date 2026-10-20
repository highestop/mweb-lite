#!/usr/bin/env python3
"""Check individual GWT cases, their index, XCTest mappings, and fixture references."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
INDEX = ROOT / "docs/testing/test-cases.md"
CASE_DIR = INDEX.parent / "cases"
FIELDS = ["ID", "Verification", "Given", "When", "Then", "Level", "Path", "Data"]
LEVELS = {"Unit", "Integration", "End-to-end"}
PATHS = {"CI", "Local script", "Preview app", "Release app"}


def links(text):
    return re.findall(r"\[[^]]+\]\(([^)]+)\)", text)


def read_case(source):
    identifier = source.stem
    if not re.fullmatch(r"[A-Z][A-Z0-9]*-\d{3}", identifier):
        raise ValueError(f"Invalid case filename: {source.name}")
    text = source.read_text()
    lines = text.strip().splitlines()
    if lines[:2] != ["| Field | Content |", "| --- | --- |"]:
        raise ValueError(f"{identifier}: expected a Field/Content table without headings or other content")
    rows = []
    for line in lines[2:]:
        if not line.startswith("| ") or not line.endswith(" |"):
            raise ValueError(f"{identifier}: each field must occupy one table row; use <br> for line breaks")
        cells = [cell.strip() for cell in re.split(r"(?<!\\)\|", line[1:-1])]
        if len(cells) != 2:
            raise ValueError(f"{identifier}: expected two columns; escape literal pipes as \\|")
        rows.append((cells[0], cells[1].replace(r"\|", "|")))
    if [field for field, _ in rows] != FIELDS:
        raise ValueError(f"{identifier}: expected exactly these ordered fields: {', '.join(FIELDS)}")
    values = dict(rows)
    if values["ID"] != identifier:
        raise ValueError(f"{identifier}: ID must match the case filename")
    if not all(values.values()):
        raise ValueError(f"{identifier}: all definition fields need content")
    return identifier, values, text


def check():
    cases = {}
    selectors = []
    sources = {INDEX: INDEX.read_text()}
    for source in sorted(CASE_DIR.glob("*.md")):
        identifier, fields, text = read_case(source)
        level, path, data = (fields[name] for name in ("Level", "Path", "Data"))
        if level not in LEVELS or path not in PATHS:
            raise ValueError(f"{identifier}: invalid level/path")
        if data != "Inline" and not data.startswith(("Fixture:", "Mixed:")):
            raise ValueError(f"{identifier}: data must be Inline, Fixture: <link>, or Mixed: <link> plus generated inputs")
        if data != "Inline":
            targets = links(data)
            fixture_root = (ROOT / "Tests/Fixtures").resolve()
            if not targets or any(not (source.parent / target).resolve().is_relative_to(fixture_root) for target in targets):
                raise ValueError(f"{identifier}: fixture data must link to its source under Tests/Fixtures")
        case_selectors = re.findall(r"\b(\w+Tests/test\w+)\b", fields["Verification"])
        for selector in case_selectors:
            if not selector.split("/", 1)[1].startswith("test_" + identifier.replace("-", "_") + "_"):
                raise ValueError(f"{identifier}: test method must explicitly contain its case ID")
        selectors.extend(case_selectors)
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
            classes = re.findall(r"class (\w+Tests): CaseReportingTestCase", source)
            if len(classes) != 1:
                raise ValueError(f"Expected one CaseReportingTestCase class in {path.name}")
            actual.update(f"{classes[0]}/{name}" for name in re.findall(r"func (test\w+)\(", source))
    if len(selectors) != len(set(selectors)):
        raise ValueError("An XCTest selector is mapped more than once")
    if set(selectors) != actual:
        raise ValueError(f"XCTest mapping mismatch; missing={sorted(actual-set(selectors))}, stale={sorted(set(selectors)-actual)}")
    preview_source = (ROOT / "Tests/PreviewIntegration/main.swift").read_text()
    emitted = set(re.findall(r'"(PV-\d{3})"', preview_source))
    if emitted != {identifier for identifier in cases if identifier.startswith("PV-")}:
        raise ValueError("Preview harness IDs do not match case files")

    for source, text in sources.items():
        for target in links(text):
            if "://" not in target and not target.startswith("#"):
                if not (source.parent / target.split("#", 1)[0]).exists():
                    raise ValueError(f"Missing link target in {source.name}: {target}")
        for fixture in re.findall(r"`((?:Preview|Library)/[^`]+)`", text):
            if not (ROOT / "Tests/Fixtures" / fixture).exists():
                raise ValueError(f"Missing fixture in {source.name}: {fixture}")
    for path in (ROOT / "Tests/Fixtures").rglob("*"):
        if path.suffix.lower() in {".db", ".sqlite", ".sqlite3", ".app", ".zip"}:
            raise ValueError(f"Generated data does not belong in source fixtures: {path}")
    print(f"PASS: {len(cases)} GWT case files, {len(actual)} XCTest mappings, {len(emitted)} preview cases; index, fixture links, and explicit test IDs are valid")


if __name__ == "__main__":
    try:
        check()
    except (ValueError, OSError) as error:
        sys.exit(str(error))
