"""Disposable encrypted SMB identities; never print passwords or private keys."""

import json
import os
from pathlib import Path
import secrets
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


def encrypt(values, recipient, destination):
    content = subprocess.check_output(
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
    replacement = destination.with_suffix(".replacement")
    replacement.write_bytes(content)
    replacement.chmod(0o600)
    replacement.replace(destination)


def rotate():
    values = document()
    values["cifs"]["password"] = secrets.token_hex(32)
    recipient = subprocess.check_output(
        ["age-keygen", "-y", str(ROOT / "identity")], text=True
    ).strip()
    encrypt(values, recipient, SOURCE)


def export_for_client():
    # Only a public recipient and ciphertext cross the VM shared directory.
    recipient = Path("/tmp/shared/cifs-client-recipient").read_text().strip()
    encrypt(document(), recipient, Path("/tmp/shared/cifs-client-source.yaml"))


def install_user():
    password = Path("/run/secrets/cifs/password").read_text().strip()
    subprocess.run(
        ["smbpasswd", "-s", "-a", "fixture-smb"],
        input=(password + "\n" + password + "\n").encode(),
        stdout=subprocess.DEVNULL,
        check=True,
    )


def audit():
    values = document()["cifs"]
    password = values["password"].encode()
    assert password not in SOURCE.read_bytes()
    rendered = Path("/run/secrets/cifs-credentials")
    assert rendered.stat().st_mode & 0o777 == 0o400
    fields = dict(line.split("=", 1) for line in rendered.read_text().splitlines())
    assert fields == values
    assert password not in Path("/etc/fstab").read_bytes()
    unit = subprocess.check_output(["systemctl", "cat", "mnt-rw.mount"])
    assert password not in unit


if sys.argv[1] == "generate":
    print(
        json.dumps(
            {
                "cifs": {
                    "username": "fixture-smb",
                    "password": secrets.token_hex(32),
                    "domain": "WORKGROUP",
                }
            }
        )
    )
else:
    {
        "rotate": rotate,
        "export": export_for_client,
        "install-user": install_user,
        "audit": audit,
    }[sys.argv[1]]()
