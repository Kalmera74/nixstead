"""Mount guards and disposable permission probes; also usable on CIFS hosts."""

import argparse
import errno
import grp
import json
import os
from pathlib import Path
import stat
import tempfile


def normalized(path):
    return (
        path.startswith("/")
        and path != "/"
        and str(Path(path)) == path
        and ".." not in Path(path).parts
    )


def verify_mounts(mounts):
    # Trigger automounts by reading, then reject autofs and missing real mounts.
    for mount in mounts:
        os.stat(mount)
        entries = Path("/proc/self/mountinfo").read_text().splitlines()
        if not any(
            line.split()[4].replace("\\040", " ") == mount
            and line.split(" - ", 1)[1].split()[0] != "autofs"
            for line in entries
        ):
            raise RuntimeError(f"Required filesystem is not mounted: {mount}")


def create_directories(paths, group, manage_existing=False):
    gid = grp.getgrnam(group).gr_gid
    for value in paths:
        path = Path(value)
        missing = []
        current = path
        while not current.exists():
            missing.append(current)
            current = current.parent
        for directory in reversed(missing):
            directory.mkdir(mode=0o2775)
            os.chown(directory, 0, gid)
            os.chmod(directory, 0o2775)
        if manage_existing and not missing:
            # Only this explicitly selected directory, never existing contents.
            os.chown(path, -1, gid)
            os.chmod(path, stat.S_IMODE(path.stat().st_mode) | 0o2070)


def probe(paths, links, hardlinks):
    for value in paths:
        with tempfile.TemporaryDirectory(
            prefix=".nixstead-probe-", dir=value
        ) as directory:
            path = Path(directory) / "create"
            path.write_bytes(b"created")
            with path.open("ab") as stream:
                stream.write(b" modified")
            path = path.rename(path.with_name("renamed"))
            assert path.read_bytes() == b"created modified"
            path.unlink()
        print(f"CRUD passed as uid={os.getuid()} gid={os.getgid()}: {value}")
    if hardlinks == "disabled":
        return
    for source, destination in links:
        same_device = os.stat(source).st_dev == os.stat(destination).st_dev
        print(
            f"Filesystem device compatibility {source} -> {destination}: {same_device}"
        )
        # st_dev alone cannot establish support (particularly on CIFS).
        with tempfile.TemporaryDirectory(prefix=".nixstead-probe-", dir=source) as src:
            with tempfile.TemporaryDirectory(
                prefix=".nixstead-probe-", dir=destination
            ) as dst:
                original = Path(src) / "source"
                linked = Path(dst) / "linked"
                original.write_bytes(b"original")
                try:
                    os.link(original, linked)
                    linked.write_bytes(b"linked")
                    if original.read_bytes() != b"linked":
                        raise OSError(errno.EIO, "Linked writes did not reach original")
                except OSError as error:
                    if hardlinks == "require":
                        raise
                    print(
                        f"WARNING: hardlink probe failed ({error.strerror}): {source} -> {destination}"
                    )
                else:
                    print(f"Hardlink passed: {source} -> {destination}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("--create", action="store_true")
    parser.add_argument("--guard-only", action="store_true")
    args = parser.parse_args()
    config = json.loads(args.configuration.read_text())
    if not all(normalized(path) for path in config["paths"] + config["mounts"]):
        raise RuntimeError("Storage paths must be normalized absolute directories")
    verify_mounts(config["mounts"])
    for value in config["paths"]:
        if Path(value).resolve() != Path(value):
            raise RuntimeError(
                f"Storage path contains a symlink; configure its actual path: {value}"
            )
    if args.create:
        create_directories(config["paths"], config["group"], config["manageExisting"])
    elif not args.guard_only:
        probe(config["paths"], config["links"], config["hardlinks"])


if __name__ == "__main__":
    main()
