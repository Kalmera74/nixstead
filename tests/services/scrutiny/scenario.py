roots = ("/var/lib/scrutiny", "/var/lib/influxdb2")
marker = "independent two-root backup wiring bytes"


def ready():
    machine.wait_for_unit("influxdb2.service")
    machine.wait_for_unit("scrutiny.service")
    machine.wait_until_succeeds(
        "curl -fsS http://127.0.0.1:28086/health | jq -e '.status == \"pass\"'"
    )
    machine.wait_until_succeeds(
        "curl -fsS http://127.0.0.1:28192/api/health | jq -e '. == {success: true}'"
    )


def populate():
    # Markers exercise both declared archive roots without claiming SMART
    # ingestion, physical disk access or historical application-data coverage.
    for root in roots:
        machine.succeed(f"printf '%s' '{marker}' > {root}/.nixstead-backup-check")
    for port in (28192, 28086):
        machine.succeed(
            f"ss -H -ltn 'sport = :{port}' | awk '{{print $4}}' | grep -Fx '127.0.0.1:{port}'"
        )


def verify():
    for root in roots:
        assert machine.succeed(f"cat {root}/.nixstead-backup-check") == marker
    machine.succeed("test -s /var/lib/scrutiny/scrutiny.db")
    machine.succeed("test -s /var/lib/influxdb2/influxd.bolt")


def erase():
    # Scrutiny's DynamicUser StateDirectory has a private backing directory.
    machine.succeed(
        "rm -rf /var/lib/scrutiny /var/lib/private/scrutiny /var/lib/influxdb2"
    )
    for root in roots:
        machine.succeed(f"test ! -e {root}")


ServiceScenario(
    machine,
    units=["scrutiny.service", "influxdb2.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
