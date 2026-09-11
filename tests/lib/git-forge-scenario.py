# ruff: noqa: F821
# Executed with the real VM driver globals and ServiceScenario.
app = machine.succeed("cat /etc/git-forge-id").strip()
roots = [f"/srv/{app}-state", f"/srv/{app}-repositories"]
marker = "independent native forge state marker"
unit = app + ".service"


def ready():
    machine.wait_for_unit(unit)
    machine.wait_until_succeeds(f"python3 /etc/git-forge-probe.py {app} ready")


def populate():
    for root in roots:
        machine.succeed(
            "printf '%s' '" + marker + "' > " + root + "/.nixstead-backup-check"
        )


def verify():
    for root in roots:
        assert machine.succeed("cat " + root + "/.nixstead-backup-check") == marker


def erase():
    for root in roots:
        machine.succeed("rm -rf " + root)
        machine.succeed("test ! -e " + root)


ServiceScenario(
    machine, units=[unit], ready=ready, populate=populate, verify=verify, erase=erase
).run(phase)
