"""Enroll credentials in SOPS before startup and publish only verified saved values."""

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time

from credential_store import (
    StoreError,
    automatic_enrollment,
    decrypt,
    fields_for,
    get,
    put,
    save_encrypted,
)
from credentials import atomic_write


@contextmanager
def host_identity(configuration):
    """Use the same age identities as sops-nix; never read an admin's keychain."""
    key_path = Path(configuration["runtimeDirectory"]) / "identity"
    identities = []
    supplied = configuration.get("ageKeyFile")
    if supplied:
        identities.append(Path(supplied).read_text())
    for path in configuration.get("sshKeyPaths", []):
        if not Path(path).exists():
            continue
        result = subprocess.run(
            ["ssh-to-age", "-private-key", "-i", path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            identities.append(result.stdout)
    if not identities:
        raise StoreError(
            "No usable host age identity; configure nixstead.secrets.age or enroll the SSH host key"
        )
    previous = os.environ.get("SOPS_AGE_KEY_FILE")
    try:
        atomic_write(key_path, "\n".join(identities), mode=0o600)
        os.environ["SOPS_AGE_KEY_FILE"] = str(key_path)
        yield
    finally:
        key_path.unlink(missing_ok=True)
        if previous is None:
            os.environ.pop("SOPS_AGE_KEY_FILE", None)
        else:
            os.environ["SOPS_AGE_KEY_FILE"] = previous


def synchronize(configuration):
    source = Path(configuration["sourceFile"])
    if (
        not source.is_absolute()
        or source.is_symlink()
        or not source.is_file()
        or str(source.resolve()).startswith("/nix/store/")
    ):
        raise StoreError(
            "Automatic sync needs an existing writable encrypted host file outside /nix/store; set arr.credentials.autoSync.sourceFile"
        )
    lock_fd = os.open(
        str(source) + ".nixstead.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
    )
    with os.fdopen(lock_fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        source_stat = source.stat()
        os.fchown(lock.fileno(), source_stat.st_uid, source_stat.st_gid)
        before = source.read_bytes()
        original = decrypt(source)
        updated = automatic_enrollment(original, configuration["registry"])
        changed = save_encrypted(source, before, original, updated)
        # A successful encrypted save and fresh decryption precede all delivery.
        saved = decrypt(source)
        if saved != updated:
            raise StoreError(
                "Encrypted source changed before delivery; retry synchronization"
            )
        selected = {}
        for service, entry in configuration["registry"].items():
            for path, _ in fields_for(service, entry).values():
                put(selected, path, get(saved, path))
            revision = get(saved, service + "/credentialRevision")
            if revision is not None:
                put(selected, service + "/credentialRevision", revision)
        content = json.dumps(selected) + "\n"
        destination = Path(configuration["documentFile"])
        if not destination.exists() or destination.read_text() != content:
            atomic_write(destination, content)
        return changed


def run(configuration, refresh=False):
    runtime = Path(configuration["runtimeDirectory"])
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    # The source lock is shared with manual sync. This outer lock also protects
    # the temporary identity and delivery/status files across systemd units.
    with (runtime / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        status_path = runtime / "status.json"
        status = json.loads(status_path.read_text()) if status_path.exists() else {}
        status.update(
            success=False,
            lastAttempt=time.time(),
            lastError="Credential synchronization has not completed",
        )
        atomic_write(status_path, json.dumps(status) + "\n", mode=0o644)
        try:
            with host_identity(configuration):
                changed = synchronize(configuration)
            if refresh:
                for service in configuration["registry"]:
                    subprocess.run(
                        [
                            "systemctl",
                            "--no-block",
                            "start",
                            f"nixstead-credential-{service}-refresh.service",
                        ],
                        check=True,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
            status.update(
                success=True,
                lastSuccess=time.time(),
                lastError=None,
                sourceUpdated=changed,
            )
        except Exception as error:
            status["lastError"] = (
                str(error)
                if isinstance(error, StoreError)
                else "Automatic credential sync failed; check source-file permissions, host SOPS identity and journal"
            )
            raise StoreError(status["lastError"]) from None
        finally:
            atomic_write(status_path, json.dumps(status) + "\n", mode=0o644)
        print(
            "Canonical SOPS credentials saved and ready for delivery"
            if changed
            else "Canonical SOPS credentials verified; no source changes"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    try:
        run(json.loads(args.configuration.read_text()), args.refresh)
    except Exception as error:
        raise SystemExit(
            str(error)
            if isinstance(error, StoreError)
            else "Automatic credential sync failed; no secret details are displayed"
        ) from None


if __name__ == "__main__":
    main()
