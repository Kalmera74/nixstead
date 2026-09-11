"""Disposable PostgreSQL client; passwords are generated and decrypted at runtime."""

import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

ROOT = Path("/var/lib/service-fixture")
SOURCE = ROOT / "secrets.yaml"
ENV = dict(os.environ, SOPS_AGE_KEY_FILE=str(ROOT / "identity"))


def document(path=SOURCE):
    return json.loads(
        subprocess.check_output(
            ["sops", "decrypt", "--output-type", "json", str(path)], env=ENV
        )
    )


def password():
    # Exercise SQL literal quoting and systemd EnvironmentFile parsing.
    return secrets.token_hex(24) + " quote' and$dollar"


def sql(statement, database="postgres"):
    credentials = document()["devdb"]["postgresql"]
    env = dict(
        os.environ,
        PGHOST="127.0.0.1",
        PGPORT="25432",
        PGUSER=credentials["rootUser"],
        PGPASSWORD=credentials["rootPassword"],
        PGDATABASE=database,
        PGCONNECT_TIMEOUT="5",
    )
    result = subprocess.run(
        ["psql", "--no-psqlrc", "-At", "--set", "ON_ERROR_STOP=1", "-c", statement],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    # Do not include stderr, command environments or decrypted material.
    assert result.returncode == 0, "Authenticated SQL operation failed"
    return result.stdout.strip()


def main():
    action = sys.argv[1]
    if action == "generate":
        print(
            json.dumps(
                {
                    "devdb": {
                        "postgresql": {
                            "rootUser": "suite_admin",
                            "rootPassword": password(),
                        }
                    }
                }
            )
        )
    elif action == "ready":
        assert sql("SELECT 1") == "1"
    elif action == "populate":
        sql("CREATE DATABASE nixstead_smoke")
        sql(
            "CREATE TABLE marker (value text); INSERT INTO marker VALUES ('postgresql-backup-smoke-9f4c7a')",
            "nixstead_smoke",
        )
    elif action == "verify":
        assert (
            sql("SELECT value FROM marker", "nixstead_smoke")
            == "postgresql-backup-smoke-9f4c7a"
        )
    else:
        raise ValueError("Unknown fixture action")


if __name__ == "__main__":
    main()
