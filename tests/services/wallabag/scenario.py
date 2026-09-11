from datetime import timedelta


state = "/var/lib/wallabag"
marker = state + "/images/nixstead-smoke-marker"


def ready():
    machine.wait_for_unit("docker-wallabag-db.service", timeout=timedelta(seconds=600))
    machine.wait_for_unit(
        "docker-wallabag-redis.service", timeout=timedelta(seconds=600)
    )
    machine.wait_for_unit("docker-wallabag.service", timeout=timedelta(seconds=600))
    machine.wait_until_succeeds(
        "curl -fsS --max-time 5 http://127.0.0.1:28218/ >/dev/null",
        timeout=timedelta(seconds=600),
    )


def populate():
    machine.succeed("printf 'wallabag-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    machine.succeed("grep -Fx 'wallabag-backup-smoke-9f4c7a' " + marker)
    machine.succeed("test -d " + state + "/db/mysql")
    machine.succeed("curl -fsS --max-time 5 http://127.0.0.1:28218/ >/dev/null")


def erase():
    machine.succeed("rm -rf " + state)
    machine.succeed("test ! -e " + state)


ServiceScenario(
    machine,
    units=[
        "docker-wallabag.service",
        "docker-wallabag-db.service",
        "docker-wallabag-redis.service",
    ],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
