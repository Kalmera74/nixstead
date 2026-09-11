probe = "python /etc/mongodb-probe.py "


def ready():
    machine.wait_for_unit("mongodb.service")
    machine.wait_until_succeeds(probe + "ready", timeout=180)


def populate():
    machine.succeed(probe + "populate")


def verify():
    machine.succeed(probe + "verify")


def erase():
    machine.succeed("rm -rf /srv/mongodb-fixture")
    machine.succeed("test ! -e /srv/mongodb-fixture")


ServiceScenario(
    machine,
    units=["mongodb.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
