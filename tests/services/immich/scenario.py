roots = ["/srv/photos"]
marker = "independent application-state smoke marker"


def ready():
    machine.wait_for_unit("immich-server.service")
    machine.wait_until_succeeds(
        "curl --location --max-time 5 -fsS http://127.0.0.1:2283/api/server/ping > /dev/null",
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
    machine.succeed("runuser -u postgres -- dropdb immich; rm -rf /srv/photos")
    for root in roots:
        machine.succeed("test ! -e " + root)


ServiceScenario(
    machine,
    units=["immich-server.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
