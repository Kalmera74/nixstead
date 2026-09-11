"""Native readiness and a small independent backup continuity marker."""

import hashlib
import json
from pathlib import Path
import sys
import urllib.request

STATE = Path("/var/lib/n8n/.n8n")
EVIDENCE = Path("/var/lib/n8n-fixture/encryption-identity")
MARKER = STATE / "nixstead-backup-fixture"
CONTENT = bytes(range(256))


def ready():
    with urllib.request.urlopen(
        "http://127.0.0.1:23467/healthz/readiness", timeout=10
    ) as response:
        assert response.status == 200


def identity():
    key = json.loads((STATE / "config").read_text())["encryptionKey"]
    assert isinstance(key, str) and key.strip()
    assert (STATE / "database.sqlite").stat().st_size > 0
    return hashlib.sha256(key.encode()).hexdigest()


if __name__ == "__main__":
    ready()
    if sys.argv[1] == "populate":
        MARKER.write_bytes(CONTENT)
        EVIDENCE.write_text(identity())
    elif sys.argv[1] == "verify":
        assert MARKER.read_bytes() == CONTENT
        assert identity() == EVIDENCE.read_text()
    elif sys.argv[1] != "ready":
        raise ValueError("Unknown fixture action")
