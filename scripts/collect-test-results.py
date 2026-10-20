#!/usr/bin/env python3
"""Create the three-field CI artifact, including only observed CI case results."""
import argparse
import json
import pathlib
import sys
from ci_results import catalog, collect, evidence_prefix, render

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--xctest", type=pathlib.Path, required=True)
parser.add_argument("--preview", type=pathlib.Path, required=True)
parser.add_argument("--run-url", required=True)
parser.add_argument("--source-sha", required=True)
parser.add_argument("--attempt", type=int, default=1)
parser.add_argument("--output", type=pathlib.Path, required=True)
parser.add_argument("--markdown", type=pathlib.Path)
parser.add_argument("--require-xctest", action="store_true")
parser.add_argument("--require-preview", action="store_true")
args = parser.parse_args()
try:
    cases = catalog()
    prefix = evidence_prefix(args.run_url, args.source_sha, args.attempt)
    rows = collect(args.xctest, args.preview, cases, prefix, args.require_xctest, args.require_preview)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")
    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text(render(rows, cases, prefix))
    print(f"Recorded {len(rows)} observed CI cases in {args.output}")
except (ValueError, OSError) as error:
    sys.exit(str(error))
