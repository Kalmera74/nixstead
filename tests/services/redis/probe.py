"""Actual Redis RESP client with runtime-encrypted disposable ACL credentials."""

import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys

ROOT = Path("/var/lib/service-fixture")
SOURCE = ROOT / "secrets.yaml"
ENV = dict(os.environ, SOPS_AGE_KEY_FILE=str(ROOT / "identity"))


def document(path=SOURCE):
    return json.loads(
        subprocess.check_output(
            ["sops", "decrypt", "--output-type", "json", str(path)], env=ENV
        )
    )


class Redis:
    def __init__(self, source=SOURCE):
        self.connection = socket.create_connection(("127.0.0.1", 26379), timeout=10)
        self.stream = self.connection.makefile("rb")
        if source is not None:
            credentials = document(source)["devdb"]["redis"]
            self.authentication = self.command(
                "AUTH", credentials["rootUser"], credentials["rootPassword"]
            )

    def command(self, *arguments):
        encoded = [str(value).encode() for value in arguments]
        request = f"*{len(encoded)}\r\n".encode()
        for value in encoded:
            request += f"${len(value)}\r\n".encode() + value + b"\r\n"
        self.connection.sendall(request)
        return self.read()

    def read(self):
        line = self.stream.readline()
        kind, value = line[:1], line[1:-2]
        if kind == b"-":
            return ("error", value.split(b" ", 1)[0])
        if kind == b"+":
            return value.decode()
        if kind == b":":
            return int(value)
        if kind == b"$":
            size = int(value)
            if size == -1:
                return None
            body = self.stream.read(size)
            assert self.stream.read(2) == b"\r\n"
            return body.decode()
        if kind == b"*":
            return [self.read() for _ in range(int(value))]
        raise AssertionError("Unexpected Redis protocol response")


def main():
    action = sys.argv[1]
    if action == "generate":
        print(
            json.dumps(
                {
                    "devdb": {
                        "redis": {
                            "rootUser": "suite_admin",
                            "rootPassword": secrets.token_hex(32),
                        }
                    }
                }
            )
        )
        return
    client = Redis()
    assert client.authentication == "OK", "ACL authentication failed"
    if action == "ready":
        assert client.command("PING") == "PONG"
    elif action == "populate":
        assert (
            client.command("SET", "nixstead:smoke", "redis-backup-smoke-9f4c7a") == "OK"
        )
    elif action == "verify":
        assert client.command("GET", "nixstead:smoke") == "redis-backup-smoke-9f4c7a"
    else:
        raise ValueError("Unknown fixture action")


if __name__ == "__main__":
    main()
