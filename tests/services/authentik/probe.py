"""Native readiness with guest-only encrypted bootstrap credentials."""

import json
from pathlib import Path
import secrets
import sys
from urllib.error import URLError
from urllib.request import Request, urlopen


def get(url, token=None):
    headers = {} if token is None else {"Authorization": "Bearer " + token}
    with urlopen(Request(url, headers=headers), timeout=10) as response:
        assert response.status == 200
        body = response.read()
        return json.loads(body) if body else None


if sys.argv[1] == "generate":
    print(
        json.dumps(
            {
                "authentik": {"secretKey": secrets.token_hex(32)},
                "fixture": {
                    "bootstrapPassword": secrets.token_hex(32),
                    "bootstrapToken": secrets.token_hex(32),
                },
            }
        )
    )
elif sys.argv[1] == "ready":
    try:
        get("http://127.0.0.1:29000/-/health/ready/")
        # Authentik 2026.5.6's Rust worker spells this route "heath";
        # other paths hit a fallback that returns 200 without checking health.
        get("http://127.0.0.1:29001/-/heath/ready/")
        token = Path("/run/secrets/fixture/bootstrapToken").read_text().strip()
        user = get("http://127.0.0.1:29000/api/v3/core/users/me/", token)["user"]
        assert user["username"] == "akadmin" and user["is_superuser"]
    except (AssertionError, OSError, URLError, ValueError, KeyError):
        raise SystemExit(1) from None
else:
    raise AssertionError("Unknown fixture operation")
