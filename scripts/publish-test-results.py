#!/usr/bin/env python3
"""Validate one trusted CI run and publish only its rendered result report."""
import argparse
import json
import os
import pathlib
import subprocess
import sys

sys.dont_write_bytecode = True
from ci_publish import APIError, GitHub, Publisher, PublishError
from e2e_results import effective_commit


def announce_pull_request(url):
    # Retain the actionable PR link even when a later protection rule rejects merging.
    print(f"Report pull request: {url}", flush=True)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write(f"\nReport pull request: [{url}]({url})\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--dry-run", action="store_true", help="Validate and render without remote or local writes")
    args = parser.parse_args()
    try:
        event = None
        if os.environ.get("GITHUB_EVENT_NAME") == "workflow_run":
            event_path = pathlib.Path(os.environ["GITHUB_EVENT_PATH"])
            if event_path.stat().st_size > 1024 * 1024:
                raise PublishError("Workflow event payload is too large")
            event = json.loads(event_path.read_text())
        elif not args.dry_run:
            raise PublishError("Live publishing is restricted to workflow_run")
        repository_path = pathlib.Path(__file__).resolve().parents[1]
        checkout_sha = None
        if not args.dry_run:
            checkout_sha = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=repository_path,
                check=True, capture_output=True, text=True, timeout=10,
            ).stdout.strip()
        publisher = Publisher(
            GitHub(), os.environ.get("GITHUB_REPOSITORY", ""),
            same_source=lambda left, right: effective_commit(repository_path, left) == effective_commit(repository_path, right),
        )
        result = publisher.publish(args.run_id, dry_run=args.dry_run, event=event,
                                   checkout_sha=checkout_sha, on_pull_request=announce_pull_request)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (APIError, ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
