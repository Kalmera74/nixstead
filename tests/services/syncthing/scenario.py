from datetime import timedelta

markers = ["/srv/syncthing-state/.nixstead-smoke-marker"]


def ready():
    machine.wait_for_unit("syncthing.service", timeout=timedelta(seconds=600))
    machine.wait_until_succeeds(
        "curl -fsSL --max-time 5 http://127.0.0.1:28384/ >/dev/null",
        timeout=timedelta(seconds=600),
    )


def populate():
    for marker in markers:
        machine.succeed("printf 'syncthing-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    for marker in markers:
        machine.succeed("grep -Fx 'syncthing-backup-smoke-9f4c7a' " + marker)


def erase():
    machine.succeed("rm -rf /srv/syncthing-state")
    machine.succeed("test ! -e /srv/syncthing-state")


ServiceScenario(
    machine,
    units=["syncthing.service", "syncthing-bootstrap-password.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
