"""Explicit SOPS enrollment and inspection. Never activates a system or service."""

import argparse
from copy import deepcopy
import fcntl
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import uuid

from credentials import extract, valid_key, verify_application


class StoreError(Exception):
    """A message safe to display without application data or secrets."""


def get(document, path):
    value = document
    for part in path.split("/"):
        if value is None:
            return None
        if not isinstance(value, dict):
            raise StoreError("SOPS credential branch must be an object")
        value = value.get(part)
    return value


def put(document, path, value):
    parts = path.split("/")
    node = document
    for part in parts[:-1]:
        node = node.setdefault(part, {})
        if not isinstance(node, dict):
            raise StoreError("Credential branch is not an object")
    node[parts[-1]] = value


def remove(document, path):
    parts = path.split("/")
    node = document
    for part in parts[:-1]:
        node = node.get(part, {})
        if not isinstance(node, dict):
            return
    node.pop(parts[-1], None)


def present(value):
    return value not in (None, "", "replace-me")


def fields_for(service, entry):
    if service == "qbittorrent":
        return {
            "username": ("qbittorrent/username", ["homepage/qbittorrentUsername"]),
            "password": ("qbittorrent/password", ["homepage/qbittorrentPassword"]),
        }
    api = entry["api"]
    return {"api-key": (api["sopsSecret"], api["previousSecrets"])}


def validate(value, field):
    if not isinstance(value, str) or not value or any(c in value for c in "\n\r\0"):
        raise StoreError("Credential must be a nonempty single-line string")
    if field == "api-key" and not valid_key(value):
        raise StoreError("API key has an unsupported format")


def read_private(path, elevate=True):
    try:
        return Path(path).read_text()
    except PermissionError:
        if not elevate:
            raise
        result = subprocess.run(
            ["sudo", "cat", "--", str(path)], stdout=subprocess.PIPE, text=True
        )
        if result.returncode:
            raise StoreError("Cannot read protected runtime credential")
        return result.stdout


def application_key(entry):
    # Parsing happens locally in memory; sudo reads only the declared state file.
    key = extract(
        entry["api"]["stateFile"], entry["api"]["format"], reader=read_private
    )
    service = entry["api"]["sopsSecret"].split("/")[0]
    if verify_application(service, entry, {"api-key": key}) != "in sync":
        raise StoreError(
            "Application key could not be verified; complete initialization and check its configured endpoint"
        )
    return key


def select_values(document, service, entry, source=None, application=application_key):
    values = {}
    sources = [source] if isinstance(source, str) else (source or [])
    consumed = set()
    if service == "qbittorrent" and "application" in sources:
        raise StoreError(
            "qBittorrent cannot disclose its plaintext password; select a SOPS source or rotate explicitly"
        )
    for field, (canonical, previous) in fields_for(service, entry).items():
        candidates = {
            path: get(document, path)
            for path in [canonical, *previous]
            if present(get(document, path))
        }
        selections = [
            item
            for item in sources
            if item in [canonical, *previous]
            or (field == "api-key" and item == "application")
        ]
        if len(selections) > 1:
            raise StoreError(f"Select exactly one source for {service}/{field}")
        selection = selections[0] if selections else None
        if selection:
            consumed.add(selection)
        if selection == "application":
            value = application(entry)
        elif selection:
            if selection not in [canonical, *previous] or selection not in candidates:
                raise StoreError(
                    f"Selected source is unavailable for {service}/{field}"
                )
            value = candidates[selection]
        elif any(not isinstance(value, str) for value in candidates.values()):
            raise StoreError(
                "Malformed SOPS credential; select a valid source explicitly"
            )
        elif len(set(candidates.values())) > 1:
            raise StoreError(
                "Conflicting SOPS sources: "
                + ", ".join(candidates)
                + "; select one with --from"
            )
        elif candidates:
            value = next(iter(candidates.values()))
        elif service != "qbittorrent":
            value = application(entry)
        else:
            raise StoreError(f"Awaiting credential setup: {canonical}")
        validate(value, field)
        values[field] = value
    if set(sources) != consumed:
        raise StoreError(
            "Selected source is not a recognized credential for this service"
        )
    return values


def enroll(
    document,
    service,
    entry,
    source=None,
    restore=False,
    rotate=False,
    application=application_key,
):
    updated = deepcopy(document)
    if restore and not all(
        present(get(document, path)) for path, _ in fields_for(service, entry).values()
    ):
        raise StoreError(
            "Cannot restore a missing canonical SOPS credential; enroll it first"
        )
    if rotate:
        if service == "qbittorrent":
            username = get(document, "qbittorrent/username")
            validate(username, "username")
            previous_username = get(document, "homepage/qbittorrentUsername")
            if present(previous_username) and previous_username != username:
                raise StoreError(
                    "Conflicting qBittorrent usernames; resolve them with sync --from before rotating"
                )
            values = {"username": username, "password": secrets.token_urlsafe(32)}
        else:
            values = {"api-key": secrets.token_hex(16)}
    else:
        values = select_values(document, service, entry, source, application)
    for field, (canonical, previous) in fields_for(service, entry).items():
        put(updated, canonical, values[field])
        for path in previous:
            remove(updated, path)
    if service == "qbittorrent":
        # The native hash is derived from the chosen plaintext password.
        remove(updated, "qbittorrent/passwordHash")
    if restore or rotate:
        put(updated, service + "/credentialRevision", uuid.uuid4().hex)
    return updated


def automatic_enrollment(document, registry):
    """Seed before startup. Existing encrypted values always take precedence."""
    updated = deepcopy(document)
    for service, entry in registry.items():
        try:
            if service == "qbittorrent":
                for field, (canonical, previous) in fields_for(service, entry).items():
                    if not any(
                        present(get(updated, path)) for path in [canonical, *previous]
                    ):
                        put(
                            updated,
                            canonical,
                            "arr" if field == "username" else secrets.token_urlsafe(32),
                        )

            def existing_or_new(metadata):
                try:
                    key = extract(
                        metadata["api"]["stateFile"],
                        metadata["api"]["format"],
                        allow_missing=True,
                    )
                except FileNotFoundError:
                    key = None
                return key or secrets.token_hex(16)

            updated = enroll(updated, service, entry, application=existing_or_new)
        except Exception as error:
            message = (
                str(error)
                if isinstance(error, StoreError)
                else "Cannot read existing application credentials; check state-file access and format"
            )
            raise StoreError(f"{service}: {message}") from None
    return updated


def sops_run(arguments, content=None):
    result = subprocess.run(
        ["sops", *arguments], input=content, capture_output=True, text=True
    )
    if result.returncode:
        raise StoreError(
            "SOPS operation failed; check the encrypted document and recipient identity"
        )
    return result.stdout


def decrypt(path):
    try:
        document = json.loads(sops_run(["decrypt", "--output-type", "json", str(path)]))
        if not isinstance(document, dict):
            raise ValueError
        return document
    except (ValueError, OSError):
        raise StoreError("Cannot read encrypted SOPS document") from None


def save_encrypted(path, before, original, updated):
    """Keep recipients and unrelated branches; only ciphertext touches disk."""
    if original == updated:
        return False
    fd, temporary = tempfile.mkstemp(
        prefix=".nixstead-credentials-", suffix=".yaml", dir=path.parent
    )
    temporary = Path(temporary)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(before)
        for branch in sorted(set(original) | set(updated)):
            if original.get(branch) == updated.get(branch):
                continue
            selector = json.dumps([branch])
            if branch in updated:
                sops_run(
                    ["set", "--value-stdin", str(temporary), selector],
                    json.dumps(updated[branch]),
                )
            else:
                sops_run(["unset", str(temporary), selector])
        if decrypt(temporary) != updated:
            raise StoreError("Encrypted update verification failed")
        if path.read_bytes() != before:
            raise StoreError(
                "SOPS document changed during synchronization; retry without overwriting that edit"
            )
        source_stat = path.stat()
        os.chown(temporary, source_stat.st_uid, source_stat.st_gid)
        os.chmod(temporary, source_stat.st_mode & 0o777)
        with temporary.open("rb") as stream:
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
        return True
    finally:
        temporary.unlink(missing_ok=True)


def managed(registry):
    return {
        name: entry
        for name, entry in registry.items()
        if entry.get("api") or name == "qbittorrent"
    }


def inspect_status(
    document, service, entry, runtime_root=Path("/run/nixstead-credentials")
):
    try:
        canonical = {
            field: get(document, path)
            for field, (path, _) in fields_for(service, entry).items()
        }
    except StoreError:
        return "invalid SOPS credential"
    if not all(present(v) for v in canonical.values()):
        return "awaiting credential setup"
    try:
        for field, value in canonical.items():
            validate(value, field)
    except StoreError:
        return "invalid SOPS credential"
    try:
        for field, (_, previous) in fields_for(service, entry).items():
            if any(
                present(get(document, path)) and get(document, path) != canonical[field]
                for path in previous
            ):
                return "conflicting SOPS sources"
    except StoreError:
        return "invalid SOPS credential"
    try:
        deployed = {
            field: read_private(runtime_root / service / field, elevate=False).rstrip(
                "\n"
            )
            for field in canonical
        }
    except (OSError, StoreError):
        return "not yet checked"
    if canonical != deployed:
        return "pending deployment"
    revision = get(document, service + "/credentialRevision") or ""
    revision_path = runtime_root / service / "revision"
    try:
        deployed_revision = (
            revision_path.read_text().strip() if revision_path.exists() else ""
        )
    except OSError:
        return "not yet checked"
    if revision != deployed_revision:
        return "pending deployment"
    try:
        from credentials import verify_application

        result = verify_application(service, entry, deployed)
    except Exception:
        return "not yet checked"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--file", required=True, type=Path)
    parser.add_argument("--runtime", action="store_true")
    parser.add_argument("--from", dest="source", action="append")
    parser.add_argument("--restore", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("command", choices=["list", "show", "sync", "rotate"])
    parser.add_argument("service", nargs="?", default="all")
    args = parser.parse_args()
    registry = managed(json.loads(args.registry.read_text()))
    if args.service != "all" and args.service not in registry:
        raise StoreError("Service does not support managed credentials")
    if args.runtime and args.command != "show":
        raise StoreError("--runtime is supported only with show")
    if (args.source or args.restore or args.dry_run) and args.command not in (
        "sync",
        "rotate",
    ):
        raise StoreError("Synchronization options require sync or rotate")
    if args.command in ("show", "rotate") and args.service == "all":
        raise StoreError("Select exactly one service")
    if args.restore and args.command != "sync":
        raise StoreError("--restore requires sync")
    if args.source and (
        args.service == "all" or args.restore or args.command == "rotate"
    ):
        raise StoreError(
            "--from requires sync with one service and cannot be combined with --restore"
        )
    if args.runtime:
        for field in fields_for(args.service, registry[args.service]):
            value = read_private(
                Path("/run/nixstead-credentials") / args.service / field
            ).rstrip("\n")
            if not value:
                raise StoreError("Awaiting credential setup")
            print(f"{args.service}/{field} (deployed runtime): {value}")
        return
    path = args.file.absolute()
    if args.command in ("sync", "rotate"):
        if (
            path.is_symlink()
            or str(path).startswith("/nix/store/")
            or not path.is_file()
        ):
            raise StoreError(
                "Sync requires an existing writable encrypted source file, outside the Nix store"
            )
        # Separate lock inode survives the atomic replacement of the document.
        lock_fd = os.open(
            str(path) + ".nixstead.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
        )
        with os.fdopen(lock_fd, "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            before = path.read_bytes()
            original = decrypt(path)
            updated = deepcopy(original)
            failures = []
            selected = (
                registry.items()
                if args.service == "all"
                else [(args.service, registry[args.service])]
            )
            for service, entry in selected:
                if args.service == "all" and not entry.get("enabled"):
                    continue
                try:
                    next_document = enroll(
                        updated,
                        service,
                        entry,
                        args.source,
                        args.restore,
                        args.command == "rotate",
                    )
                    print(
                        f"{service}: "
                        + (
                            "would update SOPS"
                            if args.dry_run
                            else "SOPS update prepared"
                        )
                        if next_document != updated
                        else f"{service}: unchanged"
                    )
                    updated = next_document
                except (StoreError, OSError, ValueError) as error:
                    failures.append(service)
                    message = (
                        str(error)
                        if isinstance(error, StoreError)
                        else "application key unavailable; complete initialization or select a SOPS source"
                    )
                    print(f"{service}: {message}")
            if not args.dry_run and save_encrypted(path, before, original, updated):
                print(
                    "Encrypted credentials updated. Automatic refresh delivers saved changes when enabled; otherwise rebuild to deploy."
                )
            if failures:
                raise StoreError(
                    "Synchronization incomplete for: " + ", ".join(failures)
                )
        return
    document = decrypt(path)
    if args.command == "list":
        for service, entry in registry.items():
            if entry.get("enabled"):
                sources = ", ".join(
                    path for path, _ in fields_for(service, entry).values()
                )
                print(
                    f"{service}: SOPS {sources}; {inspect_status(document, service, entry)}"
                )
    else:
        for field, (source, _) in fields_for(
            args.service, registry[args.service]
        ).items():
            value = get(document, source)
            if not present(value):
                raise StoreError(f"Awaiting credential setup: {source}")
            validate(value, field)
            print(f"{source} (canonical SOPS): {value}")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(
            str(error)
            if isinstance(error, StoreError)
            else "Credential operation failed; no secret details are displayed",
            file=sys.stderr,
        )
        sys.exit(1)
