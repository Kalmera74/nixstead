root = "/var/lib/audiobooks-smoke"
marker = "independent application-state smoke marker"


def ready():
    machine.wait_for_unit("audiobookshelf.service")
    machine.wait_until_succeeds(
        "curl --max-time 5 -fsS http://127.0.0.1:28206/ > /dev/null", timeout=180
    )


def populate():
    machine.succeed(
        "printf '%s' '" + marker + "' > " + root + "/.nixstead-backup-check"
    )


def verify():
    assert machine.succeed("cat " + root + "/.nixstead-backup-check") == marker


def erase():
    machine.succeed("rm -rf " + root)
    machine.succeed("test ! -e " + root)


ServiceScenario(
    machine,
    units=["audiobookshelf.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
