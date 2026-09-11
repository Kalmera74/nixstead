"""Native initial-administrator readiness with runtime-generated credentials."""

import base64
import json
from pathlib import Path
import secrets
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path("/var/lib/git-forge-fixture")
CREDENTIALS = ROOT / "credentials.json"


def generate():
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    credentials = {
        app: {
            "username": "fixture-admin",
            "email": "fixture-admin@example.test",
            "password": secrets.token_urlsafe(36),
        }
        for app in ("forgejo", "gitea")
    }
    CREDENTIALS.write_text(json.dumps(credentials))
    CREDENTIALS.chmod(0o600)
    print(
        json.dumps({app: {"initialAdmin": value} for app, value in credentials.items()})
    )


def ready(app):
    credentials = json.loads(CREDENTIALS.read_text())[app]
    authorization = base64.b64encode(
        (credentials["username"] + ":" + credentials["password"]).encode()
    ).decode()
    try:
        with urlopen(
            Request(
                "http://127.0.0.1:23000/api/v1/user",
                headers={"Authorization": "Basic " + authorization},
            ),
            timeout=5,
        ) as response:
            account = json.loads(response.read())
        assert account["login"] == credentials["username"] and account["is_admin"]
    except (HTTPError, URLError, OSError, AssertionError):
        raise SystemExit(1) from None


if sys.argv[1] == "generate":
    generate()
else:
    assert sys.argv[1] in ("forgejo", "gitea") and sys.argv[2] == "ready"
    ready(sys.argv[1])
