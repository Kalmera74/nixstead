"""Runtime-only Pi-hole v6 API peer and DNS ownership assertions."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import shutil
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen


SECRET = Path("/run/secrets/homepage/piholeApiKey")
ROOT = Path("/var/lib/pihole-fixture")
EXPECTED = ROOT / "expected-password"
OLD = ROOT / "old-password"
HOSTS = ROOT / "hosts.json"
SNAPSHOT = ROOT / "hosts.snapshot.json"
MODE = ROOT / "mode"
JOURNAL = Path("/var/lib/nixstead-pihole-dns-sync/managed-domains.json")
INITIAL_HOSTS = [
    "203.0.113.9 manual.example.net",
    "198.51.100.1 dashboard.example.test",
    "198.51.100.2 obsolete.example.test",
]
FINAL_HOSTS = [
    "203.0.113.9 manual.example.net",
    "192.0.2.10 dashboard.example.test",
    "192.0.2.10 pihole.example.test",
]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, _format, *_args):
        return

    def body(self):
        size = int(self.headers.get("Content-Length", "0"))
        return self.rfile.read(size)

    def reply(self, status, payload):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        return self.headers.get("X-FTL-SID") == "fixture-session"

    def do_POST(self):
        mode = MODE.read_text().strip() if MODE.exists() else "ok"
        if self.path != "/api/auth":
            self.reply(404, {"error": "missing"})
            return
        try:
            supplied = json.loads(self.body())["password"]
        except (json.JSONDecodeError, KeyError):
            self.reply(400, {"error": "malformed"})
            return
        if supplied != EXPECTED.read_text().strip():
            self.reply(401, {"session": {"valid": False}})
        elif mode == "malformed-auth":
            self.reply(200, b'{"session":')
        else:
            self.reply(200, {"session": {"valid": True, "sid": "fixture-session"}})

    def do_GET(self):
        mode = MODE.read_text().strip() if MODE.exists() else "ok"
        if self.path != "/api/config/dns/hosts" or not self.authorized():
            self.reply(401, {"error": "denied"})
        elif mode == "malformed-list":
            self.reply(200, b'{"config":')
        else:
            self.reply(200, {"config": {"dns": {"hosts": load_hosts()}}})

    def do_PATCH(self):
        if self.path != "/api/config" or not self.authorized():
            self.reply(401, {"error": "denied"})
            return
        try:
            hosts = json.loads(self.body())["config"]["dns"]["hosts"]
            assert all(isinstance(record, str) for record in hosts)
        except (AssertionError, json.JSONDecodeError, KeyError):
            self.reply(400, {"error": "malformed"})
            return
        HOSTS.write_text(json.dumps(hosts))
        self.reply(200, {"config": {"dns": {"hosts": hosts}}})

    def do_DELETE(self):
        if self.path == "/api/auth" and self.authorized():
            self.reply(204, b"")
        else:
            self.reply(401, {"error": "denied"})


def load_hosts():
    return json.loads(HOSTS.read_text())


def verify():
    assert sorted(load_hosts()) == sorted(FINAL_HOSTS), load_hosts()
    assert json.loads(JOURNAL.read_text()) == [
        "dashboard.example.test",
        "pihole.example.test",
    ]


def initialize():
    ROOT.mkdir(parents=True, exist_ok=True)
    if not EXPECTED.exists():
        shutil.copyfile(SECRET, EXPECTED)
    if not HOSTS.exists():
        HOSTS.write_text(json.dumps(INITIAL_HOSTS))


action = sys.argv[1]
if action == "generate":
    print(json.dumps({"homepage": {"piholeApiKey": secrets.token_urlsafe(32)}}))
elif action == "init":
    initialize()
elif action == "serve":
    ThreadingHTTPServer(("127.0.0.2", 28081), Handler).serve_forever()
elif action == "verify":
    verify()
elif action == "snapshot":
    shutil.copyfile(HOSTS, SNAPSHOT)
elif action == "verify-unchanged":
    assert HOSTS.read_bytes() == SNAPSHOT.read_bytes()
    verify()
elif action == "mode":
    MODE.write_text(sys.argv[2])
elif action == "reject-current":
    EXPECTED.write_text("a-different-valid-looking-password")
elif action == "accept-current":
    shutil.copyfile(SECRET, EXPECTED)
elif action == "old-denied":
    assert OLD.read_text().strip() != EXPECTED.read_text().strip()
    request = Request(
        "http://127.0.0.2:28081/api/auth",
        data=json.dumps({"password": OLD.read_text().strip()}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        urlopen(request, timeout=20)
    except HTTPError as error:
        assert error.status == 401, error.status
    else:
        raise AssertionError("Rotated Pi-hole credential was accepted")
else:
    raise SystemExit("Unknown Pi-hole fixture action")
