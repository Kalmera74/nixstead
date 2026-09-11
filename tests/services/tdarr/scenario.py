root = "/var/lib/transcode-smoke/server"
marker = "independent Tdarr server state marker"


def ready():
    machine.wait_for_unit("tdarr-server.service")
    machine.wait_until_succeeds(
        "curl --location --max-time 5 -fsS http://127.0.0.1:28203/ > /dev/null",
        timeout=180,
    )
    machine.wait_for_unit("tdarr-node-local.service")
    machine.succeed("test -s " + root + "/configs/Tdarr_Server_Config.json")


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
    units=["tdarr-server.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
