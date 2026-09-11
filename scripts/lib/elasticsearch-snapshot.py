#!/usr/bin/env python3
"""Export/restore TubeArchivist's native Elasticsearch snapshot repository.

The shell backup coordinator must stop application writers before backup/restore.
No raw Elasticsearch data directory is copied. Credentials are read inside the
configured container; only ta_* application indices are replaced during restore.
"""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid

REPOSITORY_ROOT = "/usr/share/elasticsearch/data/nixstead-snapshots"
REQUIRED_INDICES = {"ta_config", "ta_channel", "ta_video"}
INDEX_NAME = re.compile(r"ta_[a-z0-9_-]+\Z")
SNAPSHOT_NAME = re.compile(r"nixstead-[0-9a-f]{32}\Z")
# curl receives the Authorization header through stdin, not process arguments.
# No shell interpolation occurs on the host, including for container names.
REQUEST = r"""
set -eu
: "${ELASTIC_PASSWORD:?Missing runtime Elasticsearch password}"
authorization="$(printf 'elastic:%s' "$ELASTIC_PASSWORD" | base64 | tr -d '\n')"
request_method="$1"
request_path="$2"
request_body="$3"
set -- --silent --show-error --fail --max-time 180 --config - \
  --header 'Content-Type: application/json' --request "$request_method"
if [ -n "$request_body" ]; then
  set -- "$@" --data-binary "$request_body"
fi
printf 'header = "Authorization: Basic %s"\n' "$authorization" |
  curl "$@" "http://127.0.0.1:9200$request_path"
"""


class SnapshotError(Exception):
    """A refused or unsuccessful snapshot operation; message contains no secrets."""


def execute(arguments, *, timeout=240):
    try:
        return subprocess.run(
            arguments, check=True, capture_output=True, timeout=timeout
        ).stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as error:
        # Command output can include application data. Do not print it on failure.
        raise SnapshotError(
            "Elasticsearch container operation failed; no credentials or response body logged."
        ) from error


class Elasticsearch:
    def __init__(self, container):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", container):
            raise SnapshotError("Invalid container name.")
        self.container = container

    def request(self, method, path, payload=None):
        raw = execute(
            [
                "docker",
                "exec",
                self.container,
                "sh",
                "-c",
                REQUEST,
                "nixstead-snapshot",
                method,
                path,
                "" if payload is None else json.dumps(payload),
            ]
        )
        try:
            response = json.loads(raw)
        except (ValueError, UnicodeError) as error:
            raise SnapshotError("Malformed Elasticsearch response.") from error
        expected_type = list if path.startswith("/_cat/") else dict
        if (
            not isinstance(response, expected_type)
            or isinstance(response, dict)
            and response.get("error")
        ):
            raise SnapshotError("Elasticsearch refused the snapshot operation.")
        return response

    def ready(self):
        # A freshly created engine volume also bootstraps its security indices;
        # the production image can take more than a minute even on two vCPUs.
        for attempt in range(180):
            try:
                info = self.request("GET", "/")
                health = self.request(
                    "GET",
                    "/_cluster/health?wait_for_status=yellow&wait_for_no_initializing_shards=true&timeout=5s",
                )
                if health.get("timed_out") or health.get("status") not in {
                    "yellow",
                    "green",
                }:
                    raise SnapshotError("Elasticsearch primary shards are not ready.")
                return info
            except SnapshotError:
                if attempt == 179:
                    raise SnapshotError("Elasticsearch did not become ready.")
                time.sleep(1)

    def register(self, name, readonly=False):
        result = self.request(
            "PUT",
            f"/_snapshot/{name}",
            {
                "type": "fs",
                "settings": {
                    "location": f"{REPOSITORY_ROOT}/{name}",
                    "readonly": readonly,
                },
            },
        )
        if result.get("acknowledged") is not True:
            raise SnapshotError(
                "Snapshot repository registration was not acknowledged."
            )

    def unregister(self, name):
        if self.request("DELETE", f"/_snapshot/{name}").get("acknowledged") is not True:
            raise SnapshotError(
                "Snapshot repository unregistration was not acknowledged."
            )

    def remove_export(self, name):
        # The name is generated locally and validated; never remove a user path.
        if not SNAPSHOT_NAME.fullmatch(name):
            raise SnapshotError("Invalid temporary repository name.")
        execute(
            [
                "docker",
                "exec",
                "--user",
                "0",
                self.container,
                "rm",
                "-rf",
                "--",
                f"{REPOSITORY_ROOT}/{name}",
            ]
        )

    def export(self, name, destination):
        execute(
            [
                "docker",
                "cp",
                f"{self.container}:{REPOSITORY_ROOT}/{name}/.",
                str(destination),
            ]
        )

    def import_repository(self, name, source):
        path = f"{REPOSITORY_ROOT}/{name}"
        execute(["docker", "exec", self.container, "mkdir", "-p", "--", path])
        execute(["docker", "cp", str(source) + "/.", f"{self.container}:{path}"])
        uid = execute(["docker", "exec", self.container, "id", "-u"]).decode().strip()
        gid = execute(["docker", "exec", self.container, "id", "-g"]).decode().strip()
        if not uid.isdecimal() or not gid.isdecimal():
            raise SnapshotError("Invalid Elasticsearch container identity.")
        execute(
            [
                "docker",
                "exec",
                "--user",
                "0",
                self.container,
                "chown",
                "-R",
                f"{uid}:{gid}",
                "--",
                path,
            ]
        )


def check_indices(indices):
    if (
        not isinstance(indices, list)
        or not indices
        or any(
            not isinstance(name, str) or not INDEX_NAME.fullmatch(name)
            for name in indices
        )
        or len(set(indices)) != len(indices)
        or not REQUIRED_INDICES.issubset(indices)
    ):
        raise SnapshotError(
            "Incomplete or out-of-scope TubeArchivist snapshot indices."
        )
    return sorted(indices)


def check_snapshot(snapshot):
    if not isinstance(snapshot, dict) or snapshot.get("state") != "SUCCESS":
        raise SnapshotError("Elasticsearch snapshot was not complete.")
    indices = check_indices(snapshot.get("indices"))
    shards = snapshot.get("shards", {})
    if (
        not isinstance(shards, dict)
        or shards.get("failed") != 0
        or not isinstance(shards.get("successful"), int)
        or shards.get("successful", 0) <= 0
        or shards.get("successful") != shards.get("total")
    ):
        raise SnapshotError("Elasticsearch snapshot has incomplete shards.")
    if snapshot.get("include_global_state") is not False or snapshot.get(
        "feature_states", []
    ):
        raise SnapshotError(
            "Snapshot must exclude global state and security feature state."
        )
    return indices


def digest(stream):
    checksum = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        checksum.update(chunk)
    return checksum.hexdigest()


def write_archive(repository, snapshot, output):
    files = {}
    for path in sorted(repository.rglob("*")):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise SnapshotError("Repository contains unsupported filesystem entries.")
        if path.is_file():
            with path.open("rb") as stream:
                files[path.relative_to(repository).as_posix()] = digest(stream)
    if not files or not any(re.fullmatch(r"index-[0-9]+", name) for name in files):
        raise SnapshotError("Snapshot repository metadata is missing.")
    manifest = {
        "schema": 1,
        "snapshot": snapshot["snapshot"],
        "indices": check_snapshot(snapshot),
        "version": snapshot.get("version"),
        "files": files,
    }
    output = Path(output)
    # Keep any prior successful export intact until the complete archive validates.
    descriptor, temporary = tempfile.mkstemp(
        prefix=".elasticsearch-", dir=output.parent
    )
    os.close(descriptor)
    try:
        with tarfile.open(temporary, "w") as archive:
            raw = json.dumps(manifest, sort_keys=True).encode()
            member = tarfile.TarInfo("manifest.json")
            member.size, member.mode = len(raw), 0o600
            archive.addfile(member, io.BytesIO(raw))
            for name in files:
                archive.add(
                    repository / name, arcname="repository/" + name, recursive=False
                )
        validate_archive(temporary)
        os.replace(temporary, output)
    finally:
        Path(temporary).unlink(missing_ok=True)


def validate_archive(filename, destination=None):
    try:
        with tarfile.open(filename, "r:") as archive:
            members = archive.getmembers()
            names = [member.name for member in members]
            if len(names) != len(set(names)) or "manifest.json" not in names:
                raise SnapshotError(
                    "Snapshot archive has duplicate or missing metadata."
                )
            for member in members:
                parts = PurePosixPath(member.name).parts
                if (
                    not member.isfile()
                    or member.name.startswith("/")
                    or ".." in parts
                    or "\\" in member.name
                    or member.name != str(PurePosixPath(member.name))
                    or (
                        member.name != "manifest.json"
                        and not member.name.startswith("repository/")
                    )
                ):
                    raise SnapshotError("Unsafe snapshot archive entry.")
            metadata = archive.getmember("manifest.json")
            if metadata.size > 1024 * 1024 * 16:
                raise SnapshotError("Snapshot manifest is too large.")
            manifest = json.load(archive.extractfile(metadata))
            if (
                not isinstance(manifest, dict)
                or manifest.get("schema") != 1
                or not isinstance(manifest.get("snapshot"), str)
                or not SNAPSHOT_NAME.fullmatch(manifest["snapshot"])
                or not isinstance(manifest.get("version"), str)
                or not re.fullmatch(r"8\.[0-9]+\.[0-9]+", manifest["version"])
            ):
                raise SnapshotError(
                    "Unsupported snapshot manifest or Elasticsearch version."
                )
            check_indices(manifest.get("indices"))
            files = manifest.get("files")
            if (
                not isinstance(files, dict)
                or not files
                or set(names)
                != {"manifest.json", *("repository/" + name for name in files)}
            ):
                raise SnapshotError("Incomplete snapshot repository file set.")
            if not any(re.fullmatch(r"index-[0-9]+", name) for name in files):
                raise SnapshotError("Snapshot repository metadata is missing.")
            for name, expected in files.items():
                with archive.extractfile("repository/" + name) as stream:
                    if not isinstance(expected, str) or digest(stream) != expected:
                        raise SnapshotError("Corrupt snapshot repository file.")
            if destination is not None:
                # Manual extraction only after every member and checksum validates.
                # A fresh private destination prevents pre-existing symlink traversal.
                destination = Path(destination)
                destination.mkdir(mode=0o700)
                for name in files:
                    target = destination / name
                    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
                    with (
                        archive.extractfile("repository/" + name) as source,
                        target.open("xb") as target_stream,
                    ):
                        shutil.copyfileobj(source, target_stream)
            return manifest
    except (
        tarfile.TarError,
        ValueError,
        TypeError,
        KeyError,
        OSError,
        UnicodeError,
    ) as error:
        raise SnapshotError(
            "Invalid or incomplete Elasticsearch snapshot archive."
        ) from error


def backup(client, output):
    client.ready()
    name = "nixstead-" + uuid.uuid4().hex
    registered = False
    try:
        registered = True
        client.register(name)
        snapshot = client.request(
            "PUT",
            f"/_snapshot/{name}/{name}?wait_for_completion=true",
            {
                "indices": "ta_*",
                "ignore_unavailable": False,
                "include_global_state": False,
                "feature_states": ["none"],
                "partial": False,
            },
        ).get("snapshot")
        check_snapshot(snapshot)
        if snapshot.get("snapshot") != name:
            raise SnapshotError("Unexpected snapshot identity.")
        # Elasticsearch must not write to a repository while it is exported.
        client.unregister(name)
        registered = False
        with tempfile.TemporaryDirectory(prefix="nixstead-es-export-") as temporary:
            repository = Path(temporary) / "repository"
            repository.mkdir()
            client.export(name, repository)
            write_archive(repository, snapshot, output)
    finally:
        # Never delete a still-registered repository, even when unregister fails.
        if registered:
            client.unregister(name)
        client.remove_export(name)


def restore(client, archive):
    with tempfile.TemporaryDirectory(prefix="nixstead-es-restore-") as temporary:
        repository = Path(temporary) / "repository"
        manifest = validate_archive(archive, repository)
        current = client.ready()
        # This recovery adapter promises same-version restoration only.
        if current.get("version", {}).get("number") != manifest["version"]:
            raise SnapshotError(
                "Elasticsearch recovery requires the exact archived version; upgrades need a separate migration."
            )
        name = "nixstead-" + uuid.uuid4().hex
        registered = False
        try:
            client.import_repository(name, repository)
            registered = True
            client.register(name, readonly=True)
            snapshots = client.request(
                "GET", f"/_snapshot/{name}/{manifest['snapshot']}"
            ).get("snapshots", [])
            if (
                not isinstance(snapshots, list)
                or len(snapshots) != 1
                or check_snapshot(snapshots[0]) != sorted(manifest["indices"])
                or snapshots[0].get("snapshot") != manifest["snapshot"]
                or snapshots[0].get("version") != manifest["version"]
            ):
                raise SnapshotError(
                    "Snapshot indices do not match the verified archive manifest."
                )
            # Delete only named application indices, never wildcard/global/security
            # state. Unrelated live indices remain outside the restore boundary.
            indices = ",".join(manifest["indices"])
            existing = client.request(
                "GET", "/_cat/indices/ta_*?format=json&expand_wildcards=all"
            )
            if not isinstance(existing, list) or any(
                not isinstance(entry, dict) or not isinstance(entry.get("index"), str)
                for entry in existing
            ):
                raise SnapshotError("Malformed live index list; no indices replaced.")
            present = {entry["index"] for entry in existing}
            replacing = [name for name in manifest["indices"] if name in present]
            if replacing:
                if (
                    client.request("DELETE", "/" + ",".join(replacing)).get(
                        "acknowledged"
                    )
                    is not True
                ):
                    raise SnapshotError(
                        "Elasticsearch did not acknowledge scoped index replacement."
                    )
            result = (
                client.request(
                    "POST",
                    f"/_snapshot/{name}/{manifest['snapshot']}/_restore?wait_for_completion=true",
                    {
                        "indices": indices,
                        "include_global_state": False,
                        "feature_states": ["none"],
                        "include_aliases": True,
                        "partial": False,
                    },
                )
                .get("snapshot", {})
                .get("shards", {})
            )
            if (
                result.get("failed") != 0
                or result.get("successful", 0) <= 0
                or result.get("successful") != result.get("total")
            ):
                raise SnapshotError(
                    "Elasticsearch index restore was incomplete; affected applications must remain stopped."
                )
        finally:
            if registered:
                client.unregister(name)
            client.remove_export(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for operation in ("backup", "validate", "restore"):
        command = subparsers.add_parser(operation)
        if operation != "validate":
            command.add_argument("--container", required=True)
        command.add_argument(
            "--output" if operation == "backup" else "--archive", required=True
        )
    args = parser.parse_args()
    try:
        if args.command == "validate":
            validate_archive(args.archive)
        elif args.command == "backup":
            backup(Elasticsearch(args.container), args.output)
        else:
            restore(Elasticsearch(args.container), args.archive)
    except SnapshotError as error:
        print(f"Elasticsearch recovery: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
