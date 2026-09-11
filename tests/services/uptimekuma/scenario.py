from datetime import timedelta

markers = ["/srv/uptimekuma/.nixstead-smoke-marker"]


def ready():
    machine.wait_for_unit("docker-uptimekuma.service", timeout=timedelta(seconds=600))
    machine.wait_until_succeeds(
        "curl -fsSL --max-time 5 http://127.0.0.1:23010/ >/dev/null",
        timeout=timedelta(seconds=600),
    )


def populate():
    for marker in markers:
        machine.succeed("printf 'uptimekuma-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    for marker in markers:
        machine.succeed("grep -Fx 'uptimekuma-backup-smoke-9f4c7a' " + marker)


def erase():
    machine.succeed("rm -rf /srv/uptimekuma")
    machine.succeed("test ! -e /srv/uptimekuma")


ServiceScenario(
    machine,
    units=["docker-uptimekuma.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
