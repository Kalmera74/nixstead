from datetime import timedelta

probe = "python3 /etc/actual-probe.py"


def ready():
    machine.wait_for_unit("actual.service")
    machine.wait_until_succeeds(probe + " ready", timeout=timedelta(seconds=180))


ServiceScenario(
    machine,
    units=["actual.service"],
    ready=ready,
    populate=lambda: machine.succeed(probe + " setup"),
    verify=lambda: machine.succeed(probe + " verify"),
    erase=lambda: machine.succeed(probe + " erase"),
).run(phase)
