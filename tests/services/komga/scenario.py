from datetime import timedelta


state = "/var/lib/komga"
marker = state + "/nixstead-smoke-marker"


def ready():
    machine.wait_for_unit("komga.service", timeout=timedelta(seconds=300))
    machine.wait_for_open_port(28204)
    machine.wait_until_succeeds(
        "curl -fsS --max-time 5 http://127.0.0.1:28204/api/v1/claim | jq -e 'has(\"isClaimed\")'",
        timeout=timedelta(seconds=300),
    )
    machine.succeed("test $(systemctl show komga.service -p NRestarts --value) = 0")


def populate():
    machine.succeed("printf 'komga-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    machine.succeed("grep -Fx 'komga-backup-smoke-9f4c7a' " + marker)
    machine.succeed("test -s " + state + "/database.sqlite")
    machine.succeed(
        "curl -fsS --max-time 5 http://127.0.0.1:28204/api/v1/claim | jq -e 'has(\"isClaimed\")'"
    )


def erase():
    machine.succeed("rm -rf /var/lib/komga /var/lib/private/komga")
    machine.succeed("test ! -e /var/lib/komga; test ! -e /var/lib/private/komga")


ServiceScenario(
    machine,
    units=["komga.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
