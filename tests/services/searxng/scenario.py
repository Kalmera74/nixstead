start_all()
probe = "python /etc/searxng-engine-fixture.py "
secret = "/var/lib/searxng/environment"
secret_hash = "/var/lib/searxng-engine-fixture/secret.sha256"


def ready():
    machine.wait_for_unit("searxng-engine-fixture.service")
    machine.wait_for_unit("redis-searx.service")
    machine.wait_for_unit("searx.service")
    machine.wait_until_succeeds(probe + "verify", timeout=90)


def populate():
    machine.succeed(f"sha256sum {secret} | cut -d' ' -f1 > {secret_hash}")
    machine.succeed("ss -ltn | grep -F '127.0.0.1:28191'")


def verify():
    machine.succeed(probe + "verify")
    machine.succeed(
        f"test $(sha256sum {secret} | cut -d' ' -f1) = $(cat {secret_hash})"
    )


def erase():
    machine.succeed("rm -rf /var/lib/searxng")
    machine.succeed("test ! -e " + secret)


ServiceScenario(
    machine,
    units=["searx.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
