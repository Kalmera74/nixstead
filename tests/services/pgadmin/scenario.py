root = "/var/lib/pgadmin"
marker = "independent service backup wiring bytes"
units = ["pgadmin.service"]


def ready():
    for unit in units:
        machine.wait_for_unit(unit)
    machine.wait_for_unit("postgresql.service")
    machine.wait_until_succeeds(
        "curl --max-time 5 -fsSL http://127.0.0.1:25050/login > /dev/null"
    )


def populate():
    # This is a test-owned marker, not an application business record.
    machine.succeed(f"printf '%s' '{marker}' > {root}/.nixstead-backup-check")


def verify():
    assert machine.succeed(f"cat {root}/.nixstead-backup-check") == marker


def erase():
    machine.succeed("rm -rf " + root + " /var/lib/private/pgadmin")
    machine.succeed("test ! -e " + root)


ServiceScenario(
    machine,
    units=units,
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
