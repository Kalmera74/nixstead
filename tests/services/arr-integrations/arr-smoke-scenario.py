# ruff: noqa: F821
# The NixOS test driver supplies machine, ServiceScenario and phase.
import json
import shlex

applications = {
    "sonarr": (8989, "/var/lib/sonarr"),
    "radarr": (7878, "/var/lib/radarr"),
    "lidarr": (8686, "/var/lib/lidarr"),
    "readarr": (8787, "/var/lib/readarr"),
    "bazarr": (6767, "/var/lib/bazarr"),
    "prowlarr": (9696, "/var/lib/prowlarr"),
    "qbittorrent": (8080, "/var/lib/qBittorrent"),
    "sabnzbd": (8085, "/var/lib/sabnzbd"),
    "shelfmark": (8084, "/var/lib/shelfmark"),
}
roots = [root for _, root in applications.values()] + [
    "/var/lib/nixstead-arr-integrations"
]
marker = "independent ARR archive wiring bytes"


def ready():
    for app, (port, _) in applications.items():
        machine.wait_for_unit(f"{app}.service")
        machine.wait_until_succeeds(
            f"curl --max-time 5 -fsSL http://127.0.0.1:{port}/ > /dev/null"
        )
    machine.wait_for_unit("nixstead-arr-reconcile.timer")
    machine.wait_until_succeeds(
        "jq -e '.success == true' /var/lib/nixstead-arr-integrations/status.json"
    )
    for app in ("sonarr", "radarr", "lidarr", "readarr"):
        machine.wait_for_unit(f"docker-swaparr-{app}.service")
        machine.wait_until_succeeds(
            f"docker exec swaparr-{app} grep -q 1 /tmp/swaparr.health"
        )


def populate():
    # Test-owned markers check directory selection and a single restore. No
    # media acquisition, importing, queue persistence or library claim is made.
    for root in roots:
        machine.succeed(
            f"printf '%s' {shlex.quote(marker)} > {root}/.nixstead-backup-check"
        )
    machine.succeed("test -s /run/secrets/nixstead/credential-document")
    machine.fail(
        "runuser -u nobody -- test -r /run/secrets/nixstead/credential-document"
    )


def verify():
    for root in roots:
        assert machine.succeed(f"cat {root}/.nixstead-backup-check") == marker
    journal = json.loads(
        machine.succeed("cat /var/lib/nixstead-arr-integrations/ownership.json")
    )
    assert isinstance(journal, dict) and journal


def erase():
    machine.succeed(
        "rm -rf "
        + " ".join(shlex.quote(root) for root in roots)
        + " /var/lib/private/prowlarr /var/lib/private/shelfmark"
    )
    for root in roots:
        machine.succeed(f"test ! -e {root}")


ServiceScenario(
    machine,
    units=[f"{app}.service" for app in applications]
    + ["nixstead-arr-reconcile.timer", "nixstead-arr-reconcile.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
