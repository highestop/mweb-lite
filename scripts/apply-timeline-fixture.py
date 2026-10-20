#!/usr/bin/env python3
"""Add the Timeline or DateGroups overlay to a fresh Preview run under ignored build/."""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sqlite3
import subprocess

PROJECT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "Tests/Fixtures/Timeline"
ARTICLE_IDS = (11000, 11001, 11002, 11003, 11004, 11006)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def apply_overlay(run_name, date_groups=False):
    source = PROJECT / "Tests/Fixtures/DateGroups" if date_groups else SOURCE
    article_ids = tuple(range(12001, 12019)) if date_groups else ARTICLE_IDS
    category_id = 107 if date_groups else 106
    category_name = "Date Groups" if date_groups else "Timeline"
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", run_name):
        raise ValueError("Use the same 1–64 character run name accepted by run-preview-app.sh")
    run = PROJECT / "build/Test Runs" / run_name
    library = run / "Library"
    database_path = library / "mainlib.db"
    metadata_path = run / "run.json"
    baseline_path = library / ".fixture-baseline.json"
    for path in (PROJECT / "build", run.parent, run, library, library / "docs", database_path, metadata_path, baseline_path):
        if path.is_symlink():
            raise ValueError("The prepared run and its library paths must not be symbolic links")
    if not (run / "MWeb Lite Preview.app/Contents/Info.plist").is_file():
        raise ValueError("Prepare a new Preview run with --prepare-only before applying this overlay")
    ignored = subprocess.run(["git", "check-ignore", "--quiet", str(library)], cwd=PROJECT)
    if ignored.returncode != 0:
        raise ValueError("The prepared library must be ignored by Git")
    record = json.loads(metadata_path.read_text())
    baseline = json.loads(baseline_path.read_text())
    if record.get("fixture") != "Tests/Fixtures/Library" or baseline.get("source") != "Tests/Fixtures/Library":
        raise ValueError("This overlay requires a run prepared from the committed Library fixture")
    if record.get("fixtureVersion") != baseline.get("fixtureVersion"):
        raise ValueError("The run and library fixture versions do not match")
    if not baseline.get("files") or "mainlib.db" not in baseline["files"]:
        raise ValueError("The prepared library has no complete fixture baseline")
    for relative, expected in baseline["files"].items():
        path = library / relative
        if not path.resolve().is_relative_to(library.resolve()) or not path.is_file() or digest(path) != expected:
            raise ValueError("The library differs from its baseline; prepare a fresh run")
    for suffix in ("-wal", "-shm", "-journal"):
        if pathlib.Path(str(database_path) + suffix).exists():
            raise ValueError("The fixture database has journal files; use an unopened, fresh run")
    inputs = sorted(path for path in source.rglob("*") if path.is_file()) + [pathlib.Path(__file__).resolve()]
    for path in inputs:
        relative = str(path.relative_to(PROJECT))
        if record.get("sourceFiles", {}).get(relative) != digest(path):
            raise ValueError("Overlay inputs differ from the prepared app's source record; commit and prepare a new run")
    destinations = [library / "docs" / f"{identifier}.md" for identifier in article_ids]
    if any(path.exists() or path.is_symlink() for path in destinations):
        raise ValueError(f"{category_name} document IDs already exist; use a fresh run")

    copied = []
    database = sqlite3.connect(database_path.as_uri() + "?mode=rw", uri=True)
    try:
        with database:
            database.execute("PRAGMA foreign_keys = ON")
            if database.execute("SELECT 1 FROM cat WHERE uuid = ? OR name = ?", (category_id, category_name)).fetchone():
                raise ValueError(f"The {category_name} category already exists; use a fresh run")
            placeholders = ",".join("?" for _ in article_ids)
            if database.execute(f"SELECT 1 FROM article WHERE uuid IN ({placeholders})", article_ids).fetchone():
                raise ValueError(f"{category_name} article IDs already exist; use a fresh run")
            database.executescript("BEGIN IMMEDIATE;\n" + (source / "seed.sql").read_text())
            for destination in destinations:
                copied.append(destination)
                shutil.copyfile(source / "docs" / destination.name, destination)
            if database.execute("PRAGMA foreign_key_check").fetchall():
                raise ValueError("The overlaid fixture has invalid relationships")
    except BaseException:
        for path in copied:
            path.unlink(missing_ok=True)
        raise
    finally:
        database.close()
    return run


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_name", help="Existing unopened run prepared with run-preview-app.sh <run-name> --prepare-only")
    parser.add_argument("--date-groups", action="store_true", help="Apply the DateGroups scenario for E2E-016 instead of Timeline")
    args = parser.parse_args()
    try:
        apply_overlay(args.run_name, date_groups=args.date_groups)
        scenario = "Date Groups" if args.date_groups else "Timeline"
        count = 18 if args.date_groups else len(ARTICLE_IDS)
        print(f"Applied {scenario} to {args.run_name}: {count} new articles; All {7 + count}; existing Library articles and media preserved.")
        print(f"Launch with: ./scripts/run-preview-app.sh --reopen {args.run_name}")
    except (ValueError, OSError, sqlite3.Error) as error:
        parser.exit(1, f"{error}\n")
