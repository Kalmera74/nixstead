"""Render restricted EnvironmentFile values from per-consumer systemd credentials."""

import argparse
import json
import os
from pathlib import Path


def render(configuration, destination):
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    lines = []
    for name, source in configuration.items():
        value = (credentials / source).read_text().rstrip("\n")
        if not value or any(character in value for character in "\n\r\0"):
            raise ValueError("Runtime credential is empty or contains a line break")
        lines.append(name + "=" + json.dumps(value, ensure_ascii=False))
    destination = Path(destination)
    temporary = destination.with_suffix(".pending")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write("\n".join(lines) + "\n")
    temporary.replace(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        render(json.loads(args.configuration.read_text()), args.destination)
    except Exception:
        raise SystemExit(
            "Runtime environment delivery failed; inspect credential availability"
        ) from None


if __name__ == "__main__":
    main()
