#!/usr/bin/env python3
"""Refresh E2E outdated flags through a report-only pull request."""
import argparse
import json
import os
import pathlib
import subprocess
import sys

sys.dont_write_bytecode = True
from ci_publish import APIError, GitHub, PublishError
from e2e_publish import E2EPublisher


def announce_pull_request(url):
    print(f"Report pull request: {url}", flush=True)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
            stream.write(f"\nReport pull request: [{url}]({url})\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        event_path = pathlib.Path(os.environ["GITHUB_EVENT_PATH"])
        if event_path.stat().st_size > 1024 * 1024:
            raise PublishError("Event payload is too large")
        event = json.loads(event_path.read_text())
        publisher = E2EPublisher(GitHub(), os.environ.get("GITHUB_REPOSITORY", ""),
                                 pathlib.Path(__file__).resolve().parents[1])
        result = publisher.publish(os.environ.get("GITHUB_EVENT_NAME"), event,
                                   os.environ.get("GITHUB_REF"), int(os.environ["GITHUB_RUN_ID"]),
                                   dry_run=args.dry_run, on_pull_request=announce_pull_request)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except (APIError, ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
