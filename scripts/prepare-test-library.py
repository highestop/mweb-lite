#!/usr/bin/env python3
"""Materialize versioned fixture sources as a new, ignored test library."""
import argparse
import hashlib
import json
import pathlib
import shutil
import sqlite3

PROJECT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "Tests/Fixtures/Library"


def prepare(destination):
    destination = pathlib.Path(destination).absolute()
    build = PROJECT / "build"
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"Refusing to overwrite {destination}")
    if not destination.resolve().is_relative_to(build.resolve()) or destination.resolve() == build.resolve():
        raise ValueError("The destination must be a new directory inside the project's ignored build/ directory")
    # Create only the new directory; cleanup on failure cannot remove an existing library.
    destination.mkdir(parents=True)
    try:
        shutil.copytree(SOURCE / "docs", destination / "docs")
        with sqlite3.connect(destination / "mainlib.db") as db:
            db.execute("PRAGMA foreign_keys = ON")
            db.executescript((SOURCE / "schema.sql").read_text())
            db.executescript((SOURCE / "seed.sql").read_text())
            if db.execute("PRAGMA integrity_check").fetchone() != ("ok",):
                raise ValueError("Fixture database integrity check failed")
            if db.execute("PRAGMA foreign_key_check").fetchall():
                raise ValueError("Fixture relationships are invalid")
            manifest = json.loads((SOURCE / "manifest.json").read_text())
            active = sorted(str(row[0]) for row in db.execute("SELECT uuid FROM article WHERE state = 1"))
            if active != manifest["activeArticleIDs"]:
                raise ValueError("Fixture active articles do not match the manifest")
            for (identifier,) in db.execute("SELECT uuid FROM article"):
                if not (destination / "docs" / f"{identifier}.md").is_file():
                    raise ValueError(f"Missing fixture article {identifier}")
        baseline = {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted(destination.rglob("*")) if p.is_file()}
        (destination / ".fixture-baseline.json").write_text(json.dumps({
            "fixtureVersion": manifest["version"], "source": "Tests/Fixtures/Library",
            "files": baseline
        }, indent=2) + "\n")
    except BaseException:
        shutil.rmtree(destination)
        raise
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", help="New path under build/, e.g. 'build/Test Runs/selection/Library'")
    args = parser.parse_args()
    try:
        print(prepare(args.destination))
    except (ValueError, OSError, sqlite3.Error) as error:
        parser.exit(1, f"{error}\n")
