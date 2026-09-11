from __future__ import annotations

import os
import shutil
import tempfile
from collections.abc import Callable
from pathlib import Path

from ..commands import ensure_owned_directory, run, run_as_root
from ..model import HostConfig
from ..ui import UI
from ..validation import port, ssh_public_key


def configure(host: HostConfig, ui: UI, detect_key: str = "") -> None:
    ssh = host.ssh
    previous_mode = ssh.key_mode
    values = _validated_form(
        ui,
        "SSH connection",
        [
            (
                "port",
                "SSH port",
                str(ssh.port),
                "The same port is configured in sshd and the firewall.",
            )
        ],
        [("port", port, "Invalid SSH port: {value}")],
    )
    ssh.port = int(values["port"])
    if not ssh.key_mode:
        ssh.key_mode = "provided" if detect_key else "generated"
        ssh.authorized_key = detect_key
    mode = ui.select(
        "SSH key for the primary user",
        ["Use a public key", "Generate a keypair", "Do not use a key"],
        {"provided": 0, "generated": 1, "none": 2}.get(ssh.key_mode, 1),
    )
    ssh.key_mode = ["provided", "generated", "none"][mode]
    if previous_mode == "none" and ssh.key_mode != "none":
        ssh.password_authentication = False
    if ssh.key_mode == "provided":
        values = _validated_form(
            ui,
            "SSH public key",
            [
                (
                    "authorized_key",
                    "SSH public key for the primary user",
                    ssh.authorized_key,
                    "Paste one OpenSSH public key; private keys are rejected.",
                )
            ],
            [("authorized_key", ssh_public_key, "Invalid OpenSSH public key: {value}")],
        )
        ssh.authorized_key = values["authorized_key"]
    elif ssh.key_mode == "none":
        ssh.authorized_key = ""
        ssh.password_authentication = True
    else:
        ssh.authorized_key = ""
        ssh.private_key_path = str(
            host.user_files_directory / f"{host.host_name}-ssh-ed25519"
        )
    if ssh.key_mode != "none":
        ssh.password_authentication = ui.yes_no(
            "Allow SSH password authentication as a fallback",
            ssh.password_authentication,
        )
    ssh.root_login = ["no", "prohibit-password", "yes"][
        ui.select(
            "Root SSH login policy",
            ["Disabled", "Public keys only", "Password or public key"],
            {"no": 0, "prohibit-password": 1, "yes": 2}.get(ssh.root_login, 0),
        )
    ]


def _validated_form(
    ui: UI,
    title: str,
    fields: list[tuple[str, str, str, str]],
    validators: list[tuple[str, Callable[[str], bool], str]],
) -> dict[str, str]:
    current = fields
    while True:
        values = ui.form(title, current)
        for key, validator, message in validators:
            if not validator(values[key]):
                ui.error(message.format(value=values[key] or "<empty>"))
                current = [
                    (field_key, label, values.get(field_key, default), help_text)
                    for field_key, label, default, help_text in current
                ]
                break
        else:
            return values


def materialize(host: HostConfig, ui: UI) -> None:
    ssh = host.ssh
    if ssh.key_mode != "generated":
        return
    target = Path(ssh.private_key_path)
    if target.exists() or Path(f"{target}.pub").exists():
        if Path(f"{target}.pub").is_file():
            candidate = Path(f"{target}.pub").read_text().strip()
            if ssh_public_key(candidate):
                ssh.authorized_key = candidate
                ssh.key_mode = "provided"
                return
        raise RuntimeError(
            f"generated SSH key path already exists or is unsafe: {target}"
        )
    ensure_owned_directory(host.user_files_directory, host.user_uid)
    with tempfile.TemporaryDirectory(prefix="nixstead-ssh-key-") as temporary:
        temporary_key = Path(temporary) / "key"
        print(f"==> Generating an Ed25519 SSH keypair at {target}")
        args = [
            "ssh-keygen",
            "-q",
            "-t",
            "ed25519",
            "-a",
            "100",
            "-C",
            f"{host.user_name}@{host.host_name}",
            "-f",
            str(temporary_key),
        ]
        if not ui.tty:
            args[args.index("-f") : args.index("-f")] = ["-N", ""]
        run(args)
        candidate = Path(f"{temporary_key}.pub").read_text().strip()
        if not ssh_public_key(candidate):
            raise RuntimeError("ssh-keygen did not produce a valid public key")
        if os.geteuid() == host.user_uid:
            shutil.copyfile(temporary_key, target)
            shutil.copyfile(f"{temporary_key}.pub", f"{target}.pub")
            os.chmod(target, 0o600)
            os.chmod(f"{target}.pub", 0o644)
        else:
            run_as_root(
                [
                    "install",
                    "-m",
                    "0600",
                    "-o",
                    str(host.user_uid),
                    str(temporary_key),
                    str(target),
                ]
            )
            run_as_root(
                [
                    "install",
                    "-m",
                    "0644",
                    "-o",
                    str(host.user_uid),
                    f"{temporary_key}.pub",
                    f"{target}.pub",
                ]
            )
        ssh.authorized_key = candidate
    print(f"==> SSH private key: {target}")
    print(f"==> SSH public key:  {target}.pub")
