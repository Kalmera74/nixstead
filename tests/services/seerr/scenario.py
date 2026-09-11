roots = ["/var/lib/seerr"]
marker = "independent application-state smoke marker"


def ready():
    machine.wait_for_unit("seerr.service")
    machine.wait_until_succeeds(
        "curl --location --max-time 5 -fsS http://127.0.0.1:5055/api/v1/status > /dev/null",
        timeout=300,
    )


def populate():
    for root in roots:
        machine.succeed(
            "printf '%s' '" + marker + "' > " + root + "/.nixstead-backup-check"
        )


def verify():
    for root in roots:
        assert machine.succeed("cat " + root + "/.nixstead-backup-check") == marker


def erase():
    machine.succeed(
        "rm -rf /var/lib/private/seerr; rm /var/lib/seerr; test ! -e /var/lib/private/seerr"
    )
    for root in roots:
        machine.succeed("test ! -e " + root)


ServiceScenario(
    machine,
    units=["seerr.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
