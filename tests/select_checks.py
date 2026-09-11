"""Conservatively select runtime checks from service ownership and changed paths."""

import argparse
import json
from pathlib import Path
import subprocess

from suite_catalogue import SYSTEMS, validate


def matches(path, declared):
    return path.startswith(declared) if declared.endswith("/") else path == declared


def runtime_checks(catalogue, system):
    return {
        name
        for name, check in catalogue["checks"].items()
        if check["tier"] == "runtime" and system in check.get("systems", SYSTEMS)
    }


def canary_checks(catalogue, system):
    """Return the representative runtime checks intended for quick CI."""
    return {
        name
        for name in runtime_checks(catalogue, system)
        if catalogue["checks"][name].get("quick", False)
    }


def deduplicate(catalogue, checks):
    """Choose one stable name per shared execution after ownership selection."""
    selected = {}
    for name in sorted(checks):
        key = catalogue["checks"][name].get("executionKey", name)
        selected.setdefault(key, name)
    return sorted(selected.values())


def select(catalogue, paths, system="x86_64-linux", quick=False):
    validate(catalogue, system=system)
    runtime = runtime_checks(catalogue, system)
    fallback = canary_checks(catalogue, system) if quick else runtime
    selected = set()
    for path in paths:
        if path.startswith("docs/") or path in {
            "README.md",
            "AGENTS.md",
            "tests/README.md",
        }:
            continue
        owners = {
            name
            for name, service in catalogue["services"].items()
            if any(matches(path, p) for p in service["paths"])
            or path.startswith(f"tests/services/{name}/")
        }
        direct = {
            name
            for name in runtime
            if any(matches(path, p) for p in catalogue["checks"][name]["paths"])
        }
        if not owners and not direct:
            # Shared or unknown changes use representative canaries in quick
            # CI, while explicit full runs retain every runtime execution.
            selected |= fallback
        selected |= direct
        selected |= {
            name
            for owner in owners
            for name in catalogue["services"][owner]["relatedChecks"]
            if name in runtime
        }
        # An owned service without a runtime smoke retains its explicit gap;
        # always-run configuration checks cover it without unrelated VM jobs.
    return deduplicate(catalogue, selected)


def service_checks(catalogue, service, system="x86_64-linux"):
    """Select runtime checks related to one registry service."""
    validate(catalogue, system=system)
    if service not in catalogue["services"]:
        raise ValueError(f"Unknown service: {service}")
    runtime = runtime_checks(catalogue, system)
    return deduplicate(
        catalogue,
        {
            name
            for name in catalogue["services"][service]["relatedChecks"]
            if name in runtime
        },
    )


def shard_checks(catalogue, checks, count):
    """Greedily distribute unique executions across weighted CI shards."""
    if count <= 0:
        raise ValueError("Shard count must be positive")
    unique = deduplicate(catalogue, checks)
    shards = [{"checks": [], "weight": 0} for _ in range(min(count, len(unique)))]
    ordered = sorted(
        unique,
        key=lambda name: (-catalogue["checks"][name].get("weight", 1), name),
    )
    for name in ordered:
        target = min(
            range(len(shards)), key=lambda index: (shards[index]["weight"], index)
        )
        target_shard = shards[target]
        target_shard["checks"].append(name)
        target_shard["weight"] += catalogue["checks"][name].get("weight", 1)
    return [
        {"shard": index, "checks": sorted(shard["checks"])}
        for index, shard in enumerate(shards, start=1)
    ]


def changed_paths(base, head):
    # Resolve revisions before constructing a range; never accept option syntax.
    commits = [
        subprocess.check_output(
            ["git", "rev-parse", "--verify", "--end-of-options", f"{ref}^{{commit}}"],
            text=True,
        ).strip()
        for ref in (base, head)
    ]
    result = subprocess.check_output(
        [
            "git",
            "diff",
            "--name-only",
            "--no-renames",
            "-z",
            f"{commits[0]}...{commits[1]}",
            "--",
        ]
    )
    return [path.decode() for path in result.split(b"\0") if path]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalogue", type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--all", action="store_true")
    mode.add_argument("--base")
    mode.add_argument("--canaries", action="store_true")
    mode.add_argument("--service")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Use canaries for shared changes while retaining directly affected checks",
    )
    parser.add_argument("--shards", type=int)
    parser.add_argument("--system", choices=SYSTEMS, default="x86_64-linux")
    args = parser.parse_args()
    catalogue = json.loads(args.catalogue.read_text())
    try:
        validate(catalogue, system=args.system)
        if args.quick and args.base is None:
            raise ValueError("--quick is only valid with --base")
        if args.all:
            checks = deduplicate(catalogue, runtime_checks(catalogue, args.system))
        elif args.canaries:
            checks = deduplicate(catalogue, canary_checks(catalogue, args.system))
        elif args.service:
            checks = service_checks(catalogue, args.service, args.system)
        else:
            checks = select(
                catalogue,
                changed_paths(args.base, args.head),
                args.system,
                quick=args.quick,
            )
        matrix = (
            {"include": shard_checks(catalogue, checks, args.shards)}
            if args.shards is not None
            else {"check": checks}
        )
    except ValueError as error:
        parser.error(str(error))
    print(json.dumps(matrix, separators=(",", ":")))


if __name__ == "__main__":
    main()
