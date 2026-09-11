from __future__ import annotations

import re
import subprocess
from pathlib import Path


def host_name(value: str) -> bool:
    return (
        bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{0,62}", value))
        and value != "definitions"
    )


def user_name(value: str) -> bool:
    return bool(re.fullmatch(r"[a-z_][a-z0-9_-]*", value))


def unsigned(value: str) -> bool:
    return bool(re.fullmatch(r"[0-9]+", value))


def port(value: str) -> bool:
    return unsigned(value) and 1 <= int(value) <= 65535


def absolute_path(value: str) -> bool:
    return value.startswith("/")


def device_path(value: str) -> bool:
    return absolute_path(value) and not re.search(r"\s", value)


def nas_disk_name(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", value))


def fs_type(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value))


def mount_options(value: str) -> bool:
    return not value or bool(re.fullmatch(r"[A-Za-z0-9._=:+,-]+", value))


def disk_count(value: str) -> bool:
    return unsigned(value) and 1 <= int(value) <= 32


def ipv4(value: str) -> bool:
    pieces = value.split(".")
    return len(pieces) == 4 and all(p.isdigit() and 0 <= int(p) <= 255 for p in pieces)


def ipv4_cidr(value: str) -> bool:
    address, separator, prefix = value.partition("/")
    return bool(separator) and ipv4(address) and prefix.isdigit() and int(prefix) <= 32


def network_interface(value: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_.:+-]+", value))


def timezone(value: str) -> bool:
    return ".." not in value and (
        Path("/etc/zoneinfo", value).exists()
        or Path("/usr/share/zoneinfo", value).exists()
    )


def ssh_public_key(value: str) -> bool:
    if "\n" in value or not re.match(
        r"^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256)\s+",
        value,
    ):
        return False
    try:
        subprocess.run(
            ["ssh-keygen", "-l", "-f", "-"],
            input=value + "\n",
            text=True,
            check=True,
            capture_output=True,
        )
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def repository_path(value: str) -> bool:
    return absolute_path(value) and (Path(value) / "flake.nix").is_file()


def grub_device(value: str) -> bool:
    if value == "nodev":
        return True
    path = Path(value)
    if not path.is_block_device():
        return False
    try:
        kind = subprocess.run(
            ["lsblk", "-dn", "-o", "TYPE", value],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        return kind == "disk"
    except (OSError, subprocess.CalledProcessError):
        return True
