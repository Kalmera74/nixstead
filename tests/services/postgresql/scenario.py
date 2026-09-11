probe = "python3 /etc/postgresql-probe.py"


def ready():
    machine.wait_for_unit("postgresql.service")
    machine.wait_until_succeeds(probe + " ready")


def erase():
    machine.succeed("rm -rf /srv/postgresql; test ! -e /srv/postgresql")


ServiceScenario(
    machine,
    units=["postgresql.service"],
    ready=ready,
    populate=lambda: machine.succeed(probe + " populate"),
    verify=lambda: machine.succeed(probe + " verify"),
    erase=erase,
).run(phase)
