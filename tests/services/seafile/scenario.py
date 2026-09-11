from datetime import timedelta

probe = "python3 /etc/seafile-probe.py"


def ready():
    machine.wait_for_unit("nginx.service")
    machine.wait_for_unit("docker-seafile.service", timeout=timedelta(seconds=1200))
    machine.wait_until_succeeds(probe + " ready", timeout=timedelta(seconds=180))


def populate():
    machine.succeed(
        "test $(systemctl show docker-seafile.service -p NRestarts --value) = 0"
    )
    machine.succeed(probe + " setup")


def erase():
    machine.succeed("rm -rf /srv/seafile/data /srv/seafile/db")
    machine.succeed("test ! -e /srv/seafile/data && test ! -e /srv/seafile/db")


ServiceScenario(
    machine,
    units=[
        "docker-seafile.service",
        "docker-seafile-db.service",
        "docker-seafile-memcached.service",
    ],
    ready=ready,
    populate=populate,
    verify=lambda: machine.succeed(probe + " verify"),
    erase=erase,
).run(phase)
