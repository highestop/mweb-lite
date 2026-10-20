#!/usr/bin/env python3
"""Validate or refresh the manual E2E result table without running any test."""
import argparse
import pathlib
import re
import sys

from ci_results import catalog
from e2e_results import REPORT_PATH, SHA_PATTERN, STATUSES, read_rows, refresh, render, resolve_commit

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="Read-only format and case coverage check")
    mode.add_argument("--refresh", action="store_true", help="Update only outdated flags")
    parser.add_argument("--head-ref", default="origin/main", help="Committed revision used for freshness (default: origin/main)")
    parser.add_argument("--case", dest="case_id", help="Case whose actual result is being recorded")
    parser.add_argument("--status", choices=sorted(STATUSES))
    parser.add_argument("--commit", help="Exact full SHA of the commit that was actually tested")
    args = parser.parse_args()
    recording = any(value is not None for value in (args.case_id, args.status, args.commit))
    if recording and (args.check or not all((args.case_id, args.status, args.commit))):
        parser.error("Recording requires --case, --status, and --commit together, without --check")
    if not recording and not (args.check or args.refresh):
        parser.error("Choose --check, --refresh, or provide --case/--status/--commit")
    try:
        cases = catalog(ROOT)
        path = ROOT / REPORT_PATH
        rows = read_rows(path.read_text(), cases)
        if args.check:
            print(f"PASS: {len(rows)} E2E result rows have valid format and complete case coverage")
            return
        if recording:
            if not re.fullmatch(SHA_PATTERN, args.commit) or resolve_commit(ROOT, args.commit) != args.commit:
                raise ValueError("--commit must be an existing full commit SHA; fetch the tested commit if needed")
            target = next((row for row in rows if row["case_id"] == args.case_id), None)
            if target is None:
                raise ValueError(f"Unknown end-to-end case: {args.case_id}")
            target.update(status=args.status, commit_sha=args.commit, outdated="")
        updated = render(refresh(rows, ROOT, args.head_ref), cases)
        if updated != path.read_text():
            path.write_text(updated)
        print(f"Updated {REPORT_PATH} against {args.head_ref}; no test was run")
    except (ValueError, OSError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
