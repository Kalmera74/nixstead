"""Generate and replace encrypted VM-only WireGuard configuration sources."""

import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path("/var/lib/service-fixture")
SOURCE = ROOT / "secrets.yaml"
ENV = dict(os.environ, SOPS_AGE_KEY_FILE=str(ROOT / "identity"))


def document():
    return json.loads(
        subprocess.check_output(
            ["sops", "decrypt", "--output-type", "json", str(SOURCE)], env=ENV
        )
    )


def encrypt(values):
    recipient = subprocess.check_output(
        ["age-keygen", "-y", str(ROOT / "identity")], text=True
    ).strip()
    encrypted = subprocess.check_output(
        [
            "sops",
            "encrypt",
            "--age",
            recipient,
            "--input-type",
            "json",
            "--output-type",
            "yaml",
            "/dev/stdin",
        ],
        input=json.dumps(values).encode(),
    )
    replacement = ROOT / "secrets.replacement"
    replacement.write_bytes(encrypted)
    replacement.chmod(0o600)
    replacement.replace(SOURCE)


def install_source():
    encrypt(
        {
            "wireguard": {
                name: Path("/run/" + name + ".generated.conf").read_text()
                for name in ["work", "apps"]
            }
        }
    )


def private_key(contents):
    return next(
        line.split("=", 1)[1]
        for line in contents.splitlines()
        if line.startswith("PrivateKey=")
    )


def public_key():
    key = private_key(document()["wireguard"][sys.argv[2]])
    print(
        subprocess.check_output(["wg", "pubkey"], input=key + "\n", text=True).strip()
    )


def rotate():
    values = document()
    config = values["wireguard"]["apps"]
    key = subprocess.check_output(["wg", "genkey"], text=True).strip()
    values["wireguard"]["apps"] = config.replace(
        "PrivateKey=" + private_key(config), "PrivateKey=" + key
    )
    encrypt(values)


def audit():
    for name, contents in document()["wireguard"].items():
        key = private_key(contents).encode()
        assert key not in SOURCE.read_bytes()
        path = Path(
            "/run/work.conf" if name == "work" else "/run/secrets/wireguard/apps"
        )
        assert path.read_text() == contents
        assert path.stat().st_mode & 0o777 == 0o400
        assert path.stat().st_uid == 0
        unit = "wg-quick-work.service" if name == "work" else "apps.service"
        assert key not in subprocess.check_output(["systemctl", "cat", unit])


if sys.argv[1] == "generate":
    # Autostart is disabled. The local peer's public key is enrolled later;
    # these source slots contain no usable tunnel until that enrollment.
    print(json.dumps({"wireguard": {"apps": "", "work": ""}}))
else:
    {
        "install-source": install_source,
        "public": public_key,
        "rotate": rotate,
        "audit": audit,
    }[sys.argv[1]]()
