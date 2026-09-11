from datetime import timedelta

state = "/var/lib/linkwarden"
marker = state + "/data/nixstead-smoke-marker"
units = [
    "docker-linkwarden.service",
    "docker-linkwarden-db.service",
    "docker-linkwarden-meilisearch.service",
]


def ready():
    machine.wait_for_unit(
        "linkwarden-fixture-images.service", timeout=timedelta(seconds=1200)
    )
    for unit in units:
        machine.wait_for_unit(unit, timeout=timedelta(seconds=600))
    machine.wait_until_succeeds(
        "curl -fsSL --max-time 5 http://127.0.0.1:28219/ >/dev/null",
        timeout=timedelta(seconds=600),
    )


def populate():
    machine.succeed("printf 'linkwarden-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    machine.succeed("grep -Fx 'linkwarden-backup-smoke-9f4c7a' " + marker)
    machine.succeed("test -s " + state + "/postgres/PG_VERSION")
    machine.succeed("curl -fsSL --max-time 5 http://127.0.0.1:28219/ >/dev/null")


def erase():
    machine.succeed("rm -rf " + state)
    machine.succeed("test ! -e " + state)


ServiceScenario(
    machine,
    units=units,
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
