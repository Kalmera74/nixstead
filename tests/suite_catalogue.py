"""Validate declared evidence and render the service coverage catalogue."""

import argparse
import json
from pathlib import Path


CATEGORIES = (
    "configuration",
    "runtime",
    "persistence",
    "recovery",
    "failure",
    "upgrade",
)
SYSTEMS = ("x86_64-linux", "aarch64-linux")


def validate(catalogue, available_checks=None, system="x86_64-linux"):
    if catalogue["schemaVersion"] != 1 or catalogue["categories"] != list(CATEGORIES):
        raise ValueError("Unsupported coverage schema")
    if system not in SYSTEMS:
        raise ValueError(f"Unsupported validation architecture: {system}")
    checks, services = catalogue["checks"], catalogue["services"]
    for name, check in checks.items():
        if not check["detail"] or check["tier"] not in {"fast", "runtime"}:
            raise ValueError(f"Invalid check: {name}")
        key = check.get("executionKey", name)
        if not isinstance(key, str) or not key:
            raise ValueError(f"Invalid execution key: {name}")
        if not isinstance(check.get("quick", False), bool):
            raise ValueError(f"Invalid quick-check marker: {name}")
        weight = check.get("weight", 1)
        if isinstance(weight, bool) or not isinstance(weight, int) or weight <= 0:
            raise ValueError(f"Invalid check weight: {name}")
        if set(check["services"]) - services.keys():
            raise ValueError(f"Unknown service in {name}")
        architectures = check.get("systems", list(SYSTEMS))
        if (
            not isinstance(architectures, list)
            or not architectures
            or any(value not in SYSTEMS for value in architectures)
            or len(set(architectures)) != len(architectures)
        ):
            raise ValueError(f"Invalid check architectures: {name}")
    supported = {
        name
        for name, check in checks.items()
        if system in check.get("systems", SYSTEMS)
    }
    if available_checks is not None and supported - set(available_checks):
        raise ValueError("Catalogue references unavailable flake checks")
    for name, service in services.items():
        if service["support"] not in {"limited", "full"}:
            raise ValueError(f"Unknown support level: {name}")
        if (
            service["stateful"] is True
            and f"service-{name}-runtime" in checks
            and f"service-{name}-recovery" in checks
        ):
            raise ValueError(
                f"Redundant stateful runtime VM: {name}; recovery must cover startup"
            )
        if set(service["coverage"]) != set(CATEGORIES):
            raise ValueError(f"Missing coverage categories: {name}")
        for category, evidence in service["coverage"].items():
            status, refs = evidence["status"], evidence["checks"]
            if status not in {"scenario", "shared", "missing", "not-applicable"}:
                raise ValueError(f"Unknown coverage status: {name}/{category}")
            if (status in {"scenario", "shared"}) != bool(refs):
                raise ValueError(f"Evidence/status mismatch: {name}/{category}")
            if status == "not-applicable" and not evidence.get("reason"):
                raise ValueError(f"Not-applicable requires a reason: {name}/{category}")
            for ref in refs:
                if ref not in checks or name not in checks[ref]["services"]:
                    raise ValueError(f"Invalid evidence reference: {name}/{ref}")
        expected = {key for key, check in checks.items() if name in check["services"]}
        if set(service["relatedChecks"]) != expected:
            raise ValueError(f"Incomplete related checks: {name}")
        if service["support"] == "full":
            if service["stateful"] is None:
                raise ValueError(f"Full support requires explicit statefulness: {name}")
            required = ["configuration", "runtime", "failure"]
            if service["stateful"]:
                required += ["persistence", "recovery"]
            if any(
                service["coverage"][category]["status"] != "scenario"
                for category in required
            ):
                raise ValueError(f"Full support lacks required scenarios: {name}")


def render(catalogue):
    validate(catalogue)
    lines = [
        "# Service test coverage",
        "",
        "Generated from `lib.testCatalogue`; edit suite descriptors and test metadata, then regenerate.",
        "",
        "**Scenario** means a runnable check declares the stated evidence; it is not a recorded test pass or exhaustive coverage. "
        "**Shared** means catalogue/API assertions only. **Missing** is an explicit coverage gap. "
        "Scenario evidence does not automatically confer full support. See [verified scope](../support-matrix.md) for execution evidence.",
        "",
        "| Service | Configuration | Runtime | Persistence | Recovery | Failure | Upgrade |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for name, service in sorted(catalogue["services"].items()):
        cells = [service["coverage"][category]["status"] for category in CATEGORIES]
        lines.append(f"| [{service['name']}](#{name}) | " + " | ".join(cells) + " |")
    for name, service in sorted(catalogue["services"].items()):
        lines += ["", f'<a id="{name}"></a>', f"## {service['name']}", ""]
        state = {True: "stateful", False: "stateless", None: "unknown"}[
            service["stateful"]
        ]
        lines += [f"Support: {service['support']}. State: {state}.", ""]
        if service["suite"]:
            lines += [f"Suite: [{service['suite']}](../../{service['suite']}).", ""]
        for check in service["relatedChecks"]:
            lines.append(f"- `{check}`: {catalogue['checks'][check]['detail']}")
        for category, evidence in service["coverage"].items():
            if evidence["status"] == "not-applicable":
                lines.append(f"- {category}: not applicable. {evidence['reason']}")
        lines += ["", "Limitations: " + " ".join(service["limitations"])]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalogue", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--available-checks", type=Path)
    parser.add_argument("--system", default="x86_64-linux")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    catalogue = json.loads(args.catalogue.read_text())
    available = (
        json.loads(args.available_checks.read_text()) if args.available_checks else None
    )
    validate(catalogue, available, args.system)
    text = render(catalogue)
    if args.check:
        if args.output.read_text() != text:
            parser.error(
                "Coverage documentation is stale; regenerate tests/suite_catalogue.py output"
            )
    else:
        args.output.write_text(text)


if __name__ == "__main__":
    main()
