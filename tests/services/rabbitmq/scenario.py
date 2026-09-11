root = "/srv/rabbitmq"
marker = "independent service backup wiring bytes"
units = ["rabbitmq.service"]


def ready():
    for unit in units:
        machine.wait_for_unit(unit)
    machine.wait_for_open_port(25673)
    machine.wait_until_succeeds(
        "runuser -u rabbitmq -- rabbitmq-diagnostics -q check_running"
    )


def populate():
    # This is a test-owned marker, not an application business record.
    machine.succeed(f"printf '%s' '{marker}' > {root}/.nixstead-backup-check")


def verify():
    assert machine.succeed(f"cat {root}/.nixstead-backup-check") == marker


def erase():
    machine.succeed("rm -rf " + root + " ")
    machine.succeed("test ! -e " + root)


ServiceScenario(
    machine,
    units=units,
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
