"""Actual startup, native bootstrap identity and state-file restore markers."""

import hashlib
import json
from pathlib import Path
import secrets
import shutil
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

BASE = "http://127.0.0.1:28289"
ROOT = Path("/var/lib/actual-fixture")


def call(method, path, *, value=None, body=None, headers=None, status=200):
    headers = dict(headers or {})
    if value is not None:
        body = json.dumps(value).encode()
        headers["Content-Type"] = "application/json"
    try:
        response = urlopen(
            Request(BASE + path, data=body, headers=headers, method=method), timeout=30
        )
    except HTTPError as error:
        response = error
    with response:
        assert response.status == status, (
            f"Actual HTTP {response.status}, expected {status}"
        )
        content = response.read()
        return (
            json.loads(content)
            if content and "json" in response.headers.get("Content-Type", "")
            else content
        )


def configuration():
    return json.loads(Path("/etc/actual-fixture.json").read_text())


def password():
    return Path("/run/secrets/fixture/serverPassword").read_text().strip()


def auth():
    return json.loads((ROOT / "auth.json").read_text())


def setup():
    ROOT.mkdir(mode=0o700)
    token = call("POST", "/account/bootstrap", value={"password": password()})["data"][
        "token"
    ]
    user = call("GET", "/account/validate", headers={"X-ACTUAL-TOKEN": token})["data"]
    assert user["validated"] and user["permission"] == "ADMIN"
    markers = {}
    for name in ("dataDir", "serverFiles", "userFiles"):
        marker = Path(configuration()[name]) / ".nixstead-fixture-state"
        marker.write_bytes(secrets.token_bytes(32))
        marker.chmod(0o600)
        markers[str(marker)] = hashlib.sha256(marker.read_bytes()).hexdigest()
    (ROOT / "auth.json").write_text(
        json.dumps({"token": token, "user": user["userId"], "markers": markers})
    )
    (ROOT / "auth.json").chmod(0o600)


def verify():
    state = auth()
    user = call("GET", "/account/validate", headers={"X-ACTUAL-TOKEN": state["token"]})[
        "data"
    ]
    assert user["validated"] and user["userId"] == state["user"]
    for name, expected in state["markers"].items():
        assert hashlib.sha256(Path(name).read_bytes()).hexdigest() == expected


def main():
    action = sys.argv[1]
    if action == "generate":
        print(json.dumps({"fixture": {"serverPassword": secrets.token_hex(32)}}))
        return
    if action == "ready":
        try:
            assert call("GET", "/health")["status"] == "UP"
            assert (
                call("GET", "/info")["build"]["version"] == configuration()["version"]
            )
        except (AssertionError, URLError, OSError):
            raise SystemExit(1) from None
    elif action == "setup":
        setup()
    elif action == "verify":
        verify()
    elif action == "erase":
        current = configuration()
        # DynamicUser's public StateDirectory may be a symlink into private/.
        # Erase the original backing bytes, retaining any dangling public link
        # so the shipped restore's symlink handling is actually exercised.
        paths = {
            Path(current[name]).resolve(strict=True)
            for name in ("dataDir", "serverFiles", "userFiles")
        }
        roots = [
            path
            for path in paths
            if not any(other != path and other in path.parents for other in paths)
        ]
        for path in roots:
            assert str(path) in {
                "/srv/budget",
                "/srv/budget-files",
                "/var/lib/actual",
                "/var/lib/private/actual",
            }
            shutil.rmtree(path)
            assert not path.exists()
    else:
        raise AssertionError("Unknown fixture operation")
    print("Actual server fixture " + action + " succeeded")


if __name__ == "__main__":
    main()
