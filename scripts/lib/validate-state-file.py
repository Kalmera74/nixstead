#!/usr/bin/env python3
"""Validate staged JSON/SQLite recovery input without modifying the source.

SQLite is checked in a private copy. Nonempty WAL/journal companions are
refused: the selected profile requires a checkpointed, cleanly stopped database,
so SQLite cannot silently ignore damaged WAL frames or repair the source.
Callers must supply a quiesced/staged snapshot, not concurrently changing files.
This validates file integrity, not application schema.
"""

import argparse
from contextlib import closing
import json
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile


class CheckpointRequired(ValueError):
    pass


def regular_file(path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        raise ValueError("Expected populated regular file")


def reject_constant(_value):
    raise ValueError("Nonstandard JSON constant")


def validate_json(path, required_strings=()):
    regular_file(path)
    with path.open(encoding="utf-8") as source:
        data = json.load(source, parse_constant=reject_constant)
    for key in required_strings:
        if (
            not isinstance(data, dict)
            or not isinstance(data.get(key), str)
            or not data[key].strip()
        ):
            raise ValueError("Required nonempty JSON string is absent")


def validate_sqlite(path):
    regular_file(path)
    with path.open("rb") as source:
        if source.read(16) != b"SQLite format 3\x00" or path.stat().st_size < 100:
            raise ValueError("Invalid SQLite header")
    with tempfile.TemporaryDirectory(prefix="nixstead-state-validation-") as directory:
        copy = Path(directory) / "state.db"
        shutil.copyfile(path, copy)
        for suffix in ("-wal", "-journal"):
            companion = Path(str(path) + suffix)
            if companion.exists() or companion.is_symlink():
                if companion.is_symlink() or not companion.is_file():
                    raise ValueError("Invalid SQLite companion")
                if companion.stat().st_size:
                    raise CheckpointRequired
        with closing(
            sqlite3.connect(copy.as_uri() + "?mode=ro", uri=True)
        ) as connection:
            connection.execute("PRAGMA query_only=ON")
            connection.execute("PRAGMA trusted_schema=OFF")
            if connection.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                raise ValueError("SQLite integrity check failed")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("format", choices=("json", "sqlite"))
    parser.add_argument("path", type=Path)
    parser.add_argument("--required-strings-json", default="[]")
    args = parser.parse_args(argv)
    try:
        required_strings = json.loads(args.required_strings_json)
        if not isinstance(required_strings, list) or not all(
            isinstance(key, str) and key for key in required_strings
        ):
            raise ValueError("Invalid required JSON strings")
        if args.format == "json":
            validate_json(args.path, required_strings)
        else:
            if required_strings:
                raise ValueError("JSON fields require JSON validation")
            validate_sqlite(args.path)
    except CheckpointRequired:
        print(
            "SQLite recovery state has a nonempty WAL/journal; a checkpointed snapshot is required. Nothing changed.",
            file=sys.stderr,
        )
        return 1
    except Exception:
        # Parser/SQLite exception text may contain private application values.
        print(
            f"Invalid {args.format} recovery state file; nothing changed.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
