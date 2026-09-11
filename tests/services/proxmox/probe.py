"""Runtime-only Proxmox HTTPS peer and Homepage widget assertions."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import ssl
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen


USERNAME = Path("/run/secrets/homepage/proxmoxUsername")
PASSWORD = Path("/run/secrets/homepage/proxmoxPassword")
OLD_USERNAME = Path("/var/lib/proxmox-fixture/old-username")
OLD_PASSWORD = Path("/var/lib/proxmox-fixture/old-password")
MODE = Path("/var/lib/proxmox-fixture/mode")
BASE = "http://127.0.0.1:22526"
HOST = {"Host": "dashboard.example.test"}
RESOURCES = [
    {
        "type": "node",
        "node": "pve-fixture",
        "status": "online",
        "maxmem": 4096,
        "mem": 1024,
        "maxcpu": 4,
        "cpu": 0.5,
    },
    {
        "type": "qemu",
        "node": "pve-fixture",
        "vmid": 101,
        "template": 0,
        "status": "running",
    },
    {
        "type": "qemu",
        "node": "pve-fixture",
        "vmid": 102,
        "template": 0,
        "status": "stopped",
    },
    {
        "type": "lxc",
        "node": "pve-fixture",
        "vmid": 201,
        "template": 0,
        "status": "running",
    },
]


def token(username=USERNAME, password=PASSWORD):
    return f"PVEAPIToken={username.read_text().strip()}={password.read_text().strip()}"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, _format, *_args):
        return

    def reply(self, status, body):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        mode = MODE.read_text().strip() if MODE.exists() else "ok"
        if self.headers.get("Authorization") != token() or mode == "expired":
            self.reply(401, {"error": "denied"})
        elif self.path != "/api2/json/cluster/resources":
            self.reply(404, {"error": "missing"})
        elif mode == "malformed":
            self.reply(200, b'{"data":')
        else:
            self.reply(200, {"data": RESOURCES})


def fetch_raw(url, *, headers=None, status=200, insecure=False):
    context = ssl._create_unverified_context() if insecure else None
    try:
        response = urlopen(
            Request(url, headers=headers or {}), timeout=20, context=context
        )
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == status, (response.status, body)
    return body


def homepage_raw():
    return fetch_raw(
        BASE
        + "/api/services/proxy?group=Infrastructure&service=Proxmox&index=0&endpoint=cluster/resources",
        headers=HOST,
    )


def homepage_raw_with_status(status):
    return fetch_raw(
        BASE
        + "/api/services/proxy?group=Infrastructure&service=Proxmox&index=0&endpoint=cluster/resources",
        headers=HOST,
        status=status,
    )


def verify():
    services = json.loads(fetch_raw(BASE + "/api/services", headers=HOST))
    infrastructure = next(
        group for group in services if group["name"] == "Infrastructure"
    )
    proxmox = next(
        service
        for service in infrastructure["services"]
        if service["name"] == "Proxmox"
    )
    assert proxmox["href"] == "https://proxmox.example.internal", proxmox
    assert json.loads(homepage_raw()) == {"data": RESOURCES}
    direct = fetch_raw(
        "https://127.0.0.2:28006/api2/json/cluster/resources",
        headers={"Authorization": token()},
        insecure=True,
    )
    assert json.loads(direct) == {"data": RESOURCES}


action = sys.argv[1]
if action == "generate":
    print(
        json.dumps(
            {
                "homepage": {
                    "proxmoxUsername": "fixture@pve!homepage",
                    "proxmoxPassword": secrets.token_urlsafe(32),
                }
            }
        )
    )
elif action == "serve":
    server = ThreadingHTTPServer(("127.0.0.2", 28006), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(
        "/var/lib/proxmox-fixture/cert.pem", "/var/lib/proxmox-fixture/key.pem"
    )
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
elif action == "verify":
    verify()
elif action == "mode":
    MODE.write_text(sys.argv[2])
elif action == "malformed":
    body = homepage_raw_with_status(500)
    error = json.loads(body)
    assert error["error"]["message"] == "Invalid data", error
elif action == "old-denied":
    fetch_raw(
        "https://127.0.0.2:28006/api2/json/cluster/resources",
        headers={"Authorization": token(OLD_USERNAME, OLD_PASSWORD)},
        status=401,
        insecure=True,
    )
    verify()
else:
    raise SystemExit("Unknown Proxmox fixture action")
