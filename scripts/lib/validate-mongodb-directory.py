#!/usr/bin/env python3
"""Validate a stopped MongoDB snapshot with native startup in a disposable copy.

The worker has its own network namespace and loopback interface. It never binds
on the host network, executes shell input, or opens the source as a database.
This checks native startup and clean shutdown, not every collection data page.
"""

import argparse
import json
import os
from pathlib import Path
import resource
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time


def validate_policy(policy):
    for key in ("executable", "ip"):
        value = policy.get(key)
        if not isinstance(value, str) or not Path(value).is_absolute():
            raise ValueError("Expected absolute executable path")
    if not isinstance(policy.get("arguments"), list) or not all(
        isinstance(value, str) for value in policy["arguments"]
    ):
        raise ValueError("Expected an argument vector")
    timeout = policy.get("timeoutSeconds")
    if not isinstance(timeout, int) or not 1 <= timeout <= 300:
        raise ValueError("Invalid native startup timeout")


def copy_source(source, destination):
    if source.is_symlink() or not source.is_dir():
        raise ValueError("Expected snapshot directory")
    # Never let native recovery follow a symlink or operate on a device/FIFO.
    for directory, dirs, files in os.walk(source, followlinks=False):
        for name in dirs + files:
            mode = (Path(directory) / name).lstat().st_mode
            if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise ValueError("Snapshot contains a nonregular entry")
    shutil.copytree(source, destination)


def native_check(policy, directory, log):
    os.unshare(os.CLONE_NEWNET)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    subprocess.run(
        [policy["ip"], "link", "set", "lo", "up"],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with log.open("wb") as output:
        process = subprocess.Popen(
            [policy["executable"], *policy["arguments"], "--dbpath", str(directory)],
            cwd=directory,
            env={
                "PATH": os.defpath,
                "HOME": str(directory.parent),
                "TMPDIR": str(directory.parent),
                "LC_ALL": "C",
            },
            stdin=subprocess.DEVNULL,
            stdout=output,
            stderr=subprocess.STDOUT,
        )
        try:
            deadline = time.monotonic() + policy["timeoutSeconds"]
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise ValueError("Native startup exited")
                try:
                    with socket.create_connection(("127.0.0.1", 27017), timeout=0.2):
                        break
                except OSError:
                    time.sleep(0.1)
            else:
                raise ValueError("Native startup timed out")
            process.terminate()
            if process.wait(timeout=15) != 0:
                raise ValueError("Native shutdown failed")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


def validate_directory(policy, source):
    validate_policy(policy)
    with tempfile.TemporaryDirectory(
        prefix="nixstead-mongodb-validation-"
    ) as temporary:
        directory = Path(temporary) / "database"
        copy_source(source, directory)
        pid = os.fork()
        if pid == 0:
            try:
                os.setsid()
                native_check(policy, directory, Path(temporary) / "mongod.log")
            except Exception:
                os._exit(1)
            os._exit(0)
        finished = False
        try:
            deadline = time.monotonic() + policy["timeoutSeconds"] + 20
            while time.monotonic() < deadline:
                completed, status = os.waitpid(pid, os.WNOHANG)
                if completed:
                    finished = True
                    if os.waitstatus_to_exitcode(status) != 0:
                        raise ValueError("Native snapshot validation failed")
                    return
                time.sleep(0.1)
            raise ValueError("Snapshot validation timed out")
        finally:
            if not finished:
                # Also clean up on caller interruption, before deleting the copy.
                try:
                    os.killpg(pid, signal.SIGKILL)
                except ProcessLookupError:
                    os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)


def main():
    def interrupted(_signum, _frame):
        raise InterruptedError("Validation interrupted")

    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    try:
        validate_directory(json.load(sys.stdin), args.source)
    except Exception:
        # Native diagnostics and storage contents can contain private values.
        print(
            "Invalid MongoDB recovery directory or unavailable native isolation; nothing changed.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
