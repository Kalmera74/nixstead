from datetime import timedelta

markers = ["/srv/homeassistant-fixture/.nixstead-smoke-marker"]


def ready():
    machine.wait_for_unit("home-assistant.service", timeout=timedelta(seconds=600))
    machine.wait_until_succeeds(
        "curl -fsSL --max-time 5 http://127.0.0.1:28123/ >/dev/null",
        timeout=timedelta(seconds=600),
    )


def populate():
    machine.succeed("homeassistant-fixture populate")
    for marker in markers:
        machine.succeed("printf 'homeassistant-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    for marker in markers:
        machine.succeed("grep -Fx 'homeassistant-backup-smoke-9f4c7a' " + marker)


def erase():
    machine.succeed("rm -rf /srv/homeassistant-fixture")
    machine.succeed("test ! -e /srv/homeassistant-fixture")


ServiceScenario(
    machine,
    units=["home-assistant.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
