root = "/var/lib/kavita-smoke"
marker = "independent application-state smoke marker"


def ready():
    machine.wait_for_unit("kavita.service")
    machine.wait_until_succeeds(
        "curl --max-time 5 -fsS http://127.0.0.1:28205/ > /dev/null", timeout=180
    )


def populate():
    machine.succeed(
        "printf '%s' '" + marker + "' > " + root + "/.nixstead-backup-check"
    )
    machine.succeed("test -s " + root + "/kavita-token-key")
    machine.succeed(
        "sha256sum " + root + "/kavita-token-key > /tmp/original-kavita-key.sha256"
    )


def verify():
    assert machine.succeed("cat " + root + "/.nixstead-backup-check") == marker
    machine.succeed("sha256sum --check --status /tmp/original-kavita-key.sha256")


def erase():
    machine.succeed("rm -rf " + root)
    machine.succeed("test ! -e " + root)


ServiceScenario(
    machine,
    units=["kavita.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
