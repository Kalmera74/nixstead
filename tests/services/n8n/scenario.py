probe = "python /etc/n8n-probe.py"


def ready():
    machine.wait_for_unit("n8n.service")
    machine.wait_until_succeeds(probe + " ready >/dev/null 2>&1", timeout=600)
    machine.succeed("ss -ltn | grep -F '127.0.0.1:23467'")
    machine.fail("ss -ltn | grep -E '(0.0.0.0|\\*|\\[::\\]):23467'")


def populate():
    machine.succeed(probe + " populate")


def verify():
    machine.succeed(probe + " verify")


def erase():
    machine.succeed(
        "rm -rf /var/lib/n8n /var/lib/private/n8n; test ! -e /var/lib/n8n; test ! -e /var/lib/private/n8n"
    )


ServiceScenario(
    machine,
    units=["n8n.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
