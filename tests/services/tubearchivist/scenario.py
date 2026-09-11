roots = ["/srv/tube-smoke", "/srv/tube-media"]
marker = "independent media smoke marker"
units = [
    "docker-tubearchivist.service",
    "docker-tubearchivist-es.service",
    "docker-tubearchivist-redis.service",
]


def ready():
    for unit in units:
        machine.wait_for_unit(unit)
    machine.wait_until_succeeds(
        "curl --location --max-time 5 -fsS -H 'Host: tubearchivist.fixture.test' http://127.0.0.1:28209/health > /dev/null",
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
    machine.succeed("docker volume rm tubearchivist-es-data > /dev/null")


ServiceScenario(
    machine,
    units=units,
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
