from datetime import timedelta

sql = "runuser -u postgres -- psql --port 25434 --no-psqlrc --set ON_ERROR_STOP=1"
marker = "independent backup wiring bytes"
path = "/srv/identity/.nixstead-backup-check"


def ready():
    machine.wait_for_unit("authentik-server.service")
    machine.wait_for_unit("authentik-worker.service")
    machine.wait_until_succeeds(
        "/etc/authentik-probe ready", timeout=timedelta(seconds=600)
    )


def populate():
    # Test-owned markers check the configured SQL and filesystem archive roots;
    # they do not claim application identity/provider recovery coverage.
    machine.succeed(
        sql
        + " --dbname authentik --command \"CREATE TABLE nixstead_backup_check(value text); INSERT INTO nixstead_backup_check VALUES ('"
        + marker
        + "');\""
    )
    machine.succeed(
        f"printf '%s' '{marker}' > {path}; chown authentik:authentik {path}"
    )
    for secret in (
        "/run/secrets/authentik/secretKey",
        "/run/secrets/rendered/authentik-bootstrap.env",
    ):
        machine.succeed(f"test -s {secret}")
        machine.fail(f"runuser -u nobody -- test -r {secret}")
    for port in (29001, 29300, 29301, 29443):
        machine.succeed(
            f"ss -H -ltn 'sport = :{port}' | awk '{{print $4}}' | grep -Fx '127.0.0.1:{port}'"
        )


def verify():
    assert machine.succeed(f"cat {path}") == marker
    assert (
        machine.succeed(
            sql
            + " --dbname authentik --tuples-only --no-align --command 'SELECT value FROM nixstead_backup_check'"
        ).strip()
        == marker
    )


def erase():
    machine.succeed(sql + " --dbname postgres --command 'DROP DATABASE authentik'")
    machine.succeed("rm -rf /srv/identity; test ! -e /srv/identity")


ServiceScenario(
    machine,
    units=["authentik-server.service", "authentik-worker.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
