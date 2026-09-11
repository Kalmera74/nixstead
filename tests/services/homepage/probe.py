"""Runtime-only secret source, TrueNAS HTTP peer, and Homepage assertions."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen


SECRET = Path("/run/secrets/homepage/truenasApiKey")
OLD_SECRET = Path("/var/lib/homepage-fixture/old-token")
MODE = Path("/var/lib/homepage-fixture/mode")
BASE = "http://127.0.0.1:22525"
HOST = {"Host": "dashboard.example.test"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, _format, *_args):
        return

    def reply(self, status, data):
        body = data if isinstance(data, bytes) else json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        expected = "Bearer " + SECRET.read_text().strip()
        mode = MODE.read_text().strip() if MODE.exists() else "ok"
        if self.headers.get("Authorization") != expected:
            self.reply(401, {"error": "denied"})
        elif mode == "version-change" and self.path == "/api/v2.0/system/info":
            self.reply(404, {"error": "unsupported API version"})
        elif mode == "malformed" and self.path == "/api/v2.0/system/info":
            self.reply(200, b'{"loadavg":')
        elif self.path == "/api/v2.0/system/info":
            self.reply(200, {"loadavg": [0.25, 0.5, 0.75], "uptime_seconds": 4242})
        elif self.path == "/api/v2.0/alert/list":
            self.reply(200, [{"dismissed": False}, {"dismissed": True}])
        else:
            self.reply(404, {"error": "missing"})


def fetch_raw(path, *, headers=None, status=200):
    try:
        response = urlopen(Request(path, headers=headers or {}), timeout=20)
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == status, (response.status, body)
    return body


def fetch(path, *, headers=None, status=200):
    body = fetch_raw(path, headers=headers, status=status)
    return json.loads(body) if body else None


def homepage(path):
    return fetch(BASE + path, headers=HOST)


def verify():
    services = homepage("/api/services")
    infrastructure = next(
        group for group in services if group["name"] == "Infrastructure"
    )
    truenas = next(
        service
        for service in infrastructure["services"]
        if service["name"] == "TrueNAS"
    )
    assert truenas["href"] == "https://nas.example.internal", truenas
    shortcuts = next(group for group in services if group["name"] == "Shortcuts")
    assert any(
        service["name"] == "Fixture docs"
        and service["href"] == "https://docs.example.test"
        for service in shortcuts["services"]
    )
    status = homepage(
        "/api/services/proxy?group=Infrastructure&service=TrueNAS&index=0&endpoint=status"
    )
    alerts = homepage(
        "/api/services/proxy?group=Infrastructure&service=TrueNAS&index=0&endpoint=alerts"
    )
    assert status == {"loadavg": [0.25, 0.5, 0.75], "uptime_seconds": 4242}
    assert alerts == {"pending": 1}


action = sys.argv[1]
if action == "generate":
    print(json.dumps({"homepage": {"truenasApiKey": secrets.token_urlsafe(32)}}))
elif action == "serve":
    ThreadingHTTPServer(("127.0.0.2", 28080), Handler).serve_forever()
elif action == "verify":
    verify()
elif action == "mode":
    MODE.write_text(sys.argv[2])
elif action == "malformed":
    body = fetch_raw(
        BASE
        + "/api/services/proxy?group=Infrastructure&service=TrueNAS&index=0&endpoint=status",
        headers=HOST,
        status=500,
    )
    error = json.loads(body)
    assert error["error"]["message"] == "Invalid data", error
elif action == "old-denied":
    fetch(
        "http://127.0.0.2:28080/api/v2.0/system/info",
        headers={"Authorization": "Bearer " + OLD_SECRET.read_text().strip()},
        status=401,
    )
    verify()
else:
    raise SystemExit("Unknown Homepage fixture action")
