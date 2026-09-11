roots = ["/srv/jellyfin-state", "/srv/jellyfin-configuration"]
marker = "independent application-state smoke marker"


def ready():
    machine.wait_for_unit("jellyfin.service")
    machine.wait_until_succeeds(
        "curl --location --max-time 5 -fsS http://127.0.0.1:28096/System/Info/Public > /dev/null",
        timeout=300,
    )


def populate():
    for root in roots:
        machine.succeed(
            "printf '%s' '" + marker + "' > " + root + "/.nixstead-backup-check"
        )


def verify():
    for root in roots:
        assert machine.succeed("cat " + root + "/.nixstead-backup-check") == marker


def erase():
    machine.succeed(
        "rm -rf /srv/jellyfin-state /srv/jellyfin-configuration /var/cache/jellyfin"
    )
    for root in roots:
        machine.succeed("test ! -e " + root)


ServiceScenario(
    machine,
    units=["jellyfin.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
