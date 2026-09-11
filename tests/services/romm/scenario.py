roots = ["/srv/romm-smoke", "/srv/romm-library"]
marker = "independent media smoke marker"
units = ["docker-romm.service", "docker-romm-db.service"]


def ready():
    for unit in units:
        machine.wait_for_unit(unit)
    machine.wait_until_succeeds(
        "curl --location --max-time 5 -fsS -H 'Host: romm.fixture.test' http://127.0.0.1:28208/api/heartbeat > /dev/null",
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
    for root in roots:
        machine.succeed("rm -rf " + root)
        machine.succeed("test ! -e " + root)
    machine.succeed("docker volume rm romm-db-data romm-redis-data > /dev/null")


ServiceScenario(
    machine,
    units=units,
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
