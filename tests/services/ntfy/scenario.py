from datetime import timedelta

markers = ["/var/lib/ntfy-sh/.nixstead-smoke-marker"]


def ready():
    machine.wait_for_unit("ntfy-sh.service", timeout=timedelta(seconds=600))
    machine.wait_until_succeeds(
        "curl -fsSL --max-time 5 http://127.0.0.1:22586/v1/health | jq -e '.healthy == true'",
        timeout=timedelta(seconds=600),
    )


def populate():
    for marker in markers:
        machine.succeed("printf 'ntfy-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    for marker in markers:
        machine.succeed("grep -Fx 'ntfy-backup-smoke-9f4c7a' " + marker)


def erase():
    machine.succeed("rm -rf /var/lib/ntfy-sh /var/lib/private/ntfy-sh")
    machine.succeed("test ! -e /var/lib/ntfy-sh && test ! -e /var/lib/private/ntfy-sh")


ServiceScenario(
    machine,
    units=["ntfy-sh.service", "ntfy-bootstrap-credentials.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
