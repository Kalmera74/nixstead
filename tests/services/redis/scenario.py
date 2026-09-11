probe = "python3 /etc/redis-probe.py"


def ready():
    machine.wait_for_unit("redis.service")
    machine.wait_until_succeeds(probe + " ready")


def erase():
    machine.succeed("rm -rf /srv/redis; test ! -e /srv/redis")


ServiceScenario(
    machine,
    units=["redis.service"],
    ready=ready,
    populate=lambda: machine.succeed(probe + " populate"),
    verify=lambda: machine.succeed(probe + " verify"),
    erase=erase,
).run(phase)
