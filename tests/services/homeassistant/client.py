"""Real native Home Assistant APIs; credentials/tokens never leave the VM."""

import json
import secrets
import sys

if sys.argv[1] == "generate":
    print(json.dumps({"fixture": {"homeassistantPassword": secrets.token_hex(32)}}))
    raise SystemExit

from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:28123"
CLIENT = BASE + "/"
SECRET = Path("/run/secrets/fixture/homeassistantPassword")


def call(method, path, payload=None, token=None, form=False, expected=200):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = None
    if payload is not None:
        headers["Content-Type"] = (
            "application/x-www-form-urlencoded" if form else "application/json"
        )
        data = (
            urllib.parse.urlencode(payload) if form else json.dumps(payload)
        ).encode()
    try:
        with urllib.request.urlopen(
            urllib.request.Request(
                BASE + path, data=data, headers=headers, method=method
            ),
            timeout=30,
        ) as response:
            status, body = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, body = error.code, error.read()
    assert status == expected, (method, path, status, expected)
    return json.loads(body) if body and status == 200 else None


def token_from_code(code):
    return call(
        "POST",
        "/auth/token",
        {"grant_type": "authorization_code", "code": code, "client_id": CLIENT},
        form=True,
    )


def populate():
    pending = call("GET", "/api/onboarding")
    assert not next(step["done"] for step in pending if step["step"] == "user")
    onboarding = call(
        "POST",
        "/api/onboarding/users",
        {
            "name": "Fixture Owner",
            "username": "fixture-owner",
            "password": SECRET.read_text().strip(),
            "client_id": CLIENT,
            "language": "en",
        },
    )
    tokens = token_from_code(onboarding["auth_code"])
    token = tokens["access_token"]
    for step in ["core_config", "analytics"]:
        call("POST", "/api/onboarding/" + step, {}, token)
    call(
        "POST",
        "/api/onboarding/integration",
        {"client_id": CLIENT, "redirect_uri": CLIENT},
        token,
    )


if sys.argv[1] != "populate":
    raise ValueError("expected populate")
populate()
