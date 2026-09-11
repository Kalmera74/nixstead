"""Generate a disposable MongoDB secret and maintain one recovery marker."""

import json
from pathlib import Path
import secrets
import sys


if sys.argv[1] == "generate":
    print(
        json.dumps(
            {"devdb": {"mongodb": {"rootPassword": "Mongo-" + secrets.token_hex(24)}}}
        )
    )
    raise SystemExit

from pymongo import MongoClient


def connect():
    return MongoClient(
        "127.0.0.1",
        23456,
        username="root",
        password=Path("/run/secrets/devdb/mongodb/rootPassword")
        .read_text()
        .rstrip("\n"),
        authSource="admin",
        serverSelectionTimeoutMS=3000,
        connectTimeoutMS=3000,
    )


def ready():
    with connect() as client:
        assert client.admin.command("ping")["ok"] == 1


def populate():
    with connect() as client:
        client.fixture.smoke.replace_one(
            {"_id": "nixstead-backup-smoke"},
            {"_id": "nixstead-backup-smoke", "value": "mongo-marker-9f4c7a"},
            upsert=True,
        )


def verify():
    with connect() as client:
        assert client.fixture.smoke.find_one({"_id": "nixstead-backup-smoke"}) == {
            "_id": "nixstead-backup-smoke",
            "value": "mongo-marker-9f4c7a",
        }


{"ready": ready, "populate": populate, "verify": verify}[sys.argv[1]]()
