"""Inspect deployed storage and optionally probe a running writer's permissions."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("--service", required=True)
    parser.add_argument(
        "--probe",
        action="store_true",
        help="create and remove disposable probe files in the running service's mount namespace",
    )
    args = parser.parse_args()
    configuration = json.loads(args.configuration.read_text())
    if args.service not in configuration["services"]:
        parser.error("select one of: " + ", ".join(configuration["services"]))
    for command in ("systemctl", "findmnt", "nsenter", "setpriv"):
        if shutil.which(command) is None:
            parser.error("required command is unavailable: " + command)
    spec = configuration["services"][args.service]
    for path in json.loads(Path(spec).read_text())["paths"]:
        subprocess.run(
            ["findmnt", "--target", path, "--output", "TARGET,SOURCE,FSTYPE,OPTIONS"],
            check=True,
        )
    if not args.probe:
        print(
            "Use --probe as root for disposable CRUD/hardlink checks as the running service."
        )
        return
    if os.geteuid() != 0:
        parser.error(
            "--probe requires root to enter the service mount namespace and drop to its identity"
        )
    pid = subprocess.check_output(
        [
            "systemctl",
            "show",
            args.service + ".service",
            "--property=MainPID",
            "--value",
        ],
        text=True,
    ).strip()
    if not pid.isdecimal() or int(pid) == 0:
        parser.error("the selected service must be running")
    status = dict(
        line.split(":", 1)
        for line in Path(f"/proc/{pid}/status").read_text().splitlines()
        if ":" in line
    )
    uid, gid = status["Uid"].split()[1], status["Gid"].split()[1]
    groups = status["Groups"].split()
    group_argument = ["--groups", ",".join(groups)] if groups else ["--clear-groups"]
    os.umask(0o002)
    subprocess.run(
        [
            "nsenter",
            "--target",
            pid,
            "--mount",
            "--root",
            "--wd=/",
            "--",
            "setpriv",
            "--reuid",
            uid,
            "--regid",
            gid,
            *group_argument,
            configuration["python"],
            configuration["probe"],
            spec,
        ],
        check=True,
    )
    print(
        "Probes passed in the running mount namespace. Startup validation additionally uses the complete service sandbox."
    )


if __name__ == "__main__":
    main()
