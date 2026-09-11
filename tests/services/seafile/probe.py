"""Pinned Seafile readiness and a small combined-state restore marker."""

import hashlib
import json
from pathlib import Path
import secrets
import ssl
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE = "https://seafile.fixture.test"
ROOT = Path("/var/lib/seafile-fixture")
DATA = Path("/srv/seafile/data")


def call(path, *, token=None, form=None):
    headers = {"Authorization": "Token " + token} if token else {}
    body = None
    if form is not None:
        body = urlencode(form).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    context = ssl.create_default_context(cafile="/var/lib/nginx/local-ca/ca.crt")
    try:
        response = urlopen(
            Request(BASE + path, data=body, headers=headers),
            context=context,
            timeout=45,
        )
    except HTTPError as error:
        raise AssertionError(f"Seafile HTTP {error.code}") from None
    with response:
        return json.loads(response.read())


def configuration():
    return {
        name: hashlib.sha256((DATA / "seafile/conf" / name).read_bytes()).hexdigest()
        for name in ("ccnet.conf", "seafile.conf", "seahub_settings.py")
    }


def setup():
    ROOT.mkdir(mode=0o700)
    token = call(
        "/api2/auth-token/",
        form={
            "username": "admin@fixture.test",
            "password": Path("/run/secrets/seafile/adminPassword").read_text().strip(),
        },
    )["token"]
    account = call("/api2/account/info/", token=token)
    assert (account["contact_email"] or account["email"]) == "admin@fixture.test"
    marker = DATA / ".nixstead-fixture-state"
    marker.write_bytes(secrets.token_bytes(32))
    marker.chmod(0o600)
    state = {
        "token": token,
        "user": account["email"],
        "configuration": configuration(),
        "marker": hashlib.sha256(marker.read_bytes()).hexdigest(),
    }
    (ROOT / "expected.json").write_text(json.dumps(state))
    (ROOT / "expected.json").chmod(0o600)


def verify():
    state = json.loads((ROOT / "expected.json").read_text())
    account = call("/api2/account/info/", token=state["token"])
    assert account["email"] == state["user"] and account["is_staff"]
    assert configuration() == state["configuration"]
    assert (
        hashlib.sha256((DATA / ".nixstead-fixture-state").read_bytes()).hexdigest()
        == state["marker"]
    )


def main():
    action = sys.argv[1]
    if action == "generate":
        print(
            json.dumps(
                {
                    "seafile": {
                        "adminEmail": "admin@fixture.test",
                        "adminPassword": secrets.token_hex(24),
                        "dbRootPassword": secrets.token_hex(24),
                    }
                }
            )
        )
        return
    if action == "ready":
        try:
            assert call("/api2/ping/") == "pong"
        except (AssertionError, URLError, OSError):
            raise SystemExit(1) from None
    elif action == "setup":
        setup()
    elif action == "verify":
        verify()
    else:
        raise AssertionError("Unknown Seafile smoke operation")
    print("Seafile smoke " + action + " succeeded")


if __name__ == "__main__":
    main()
