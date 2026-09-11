sql = "runuser -u postgres -- psql --port 25432 --no-psqlrc --set ON_ERROR_STOP=1"
marker = "independent SQL backup wiring bytes"
root = "/var/lib/miniflux"


def ready():
    machine.wait_for_unit("miniflux.service")
    machine.wait_until_succeeds(
        "curl --max-time 5 -fsSL http://127.0.0.1:28190/healthcheck > /dev/null"
    )


def populate():
    # Independent SQL/file markers verify both archive inputs without a feed
    # workflow, account changes or lifecycle/failure loops.
    machine.succeed(
        sql
        + " --dbname miniflux --command \"CREATE TABLE nixstead_backup_check(value text); INSERT INTO nixstead_backup_check VALUES ('"
        + marker
        + "');\""
    )
    machine.succeed(f"printf '%s' '{marker}' > {root}/.nixstead-backup-check")


def verify():
    assert machine.succeed(f"cat {root}/.nixstead-backup-check") == marker
    assert (
        machine.succeed(
            sql
            + " --dbname miniflux --tuples-only --no-align --command 'SELECT value FROM nixstead_backup_check'"
        ).strip()
        == marker
    )


def erase():
    machine.succeed(sql + " --dbname postgres --command 'DROP DATABASE miniflux'")
    machine.succeed("rm -rf " + root)
    machine.succeed("test ! -e " + root)


ServiceScenario(
    machine,
    units=["miniflux.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
