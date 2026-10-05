state = "/srv/radicale"
marker = state + "/collections/nixstead-recovery-marker"
password = state + "/admin-password"
users = state + "/users"
url = "http://127.0.0.1:25232/admin/"


def ready():
    machine.wait_for_unit("radicale.service")
    machine.wait_for_open_port(25232)
    machine.succeed(
        "test $(curl -sS -o /dev/null -w '%{http_code}' -X PROPFIND "
        "-H 'Depth: 0' " + url + ") = 401"
    )
    machine.succeed(
        "test $(curl -sS -o /dev/null -w '%{http_code}' -X PROPFIND "
        f"-H 'Depth: 0' -u \"admin:$(cat {password})\" " + url + ") = 207"
    )


def populate():
    machine.succeed("ss -ltn | grep -F '127.0.0.1:25232'")
    machine.succeed(f"test $(stat -c %a {password}) = 600")
    machine.succeed(f"test $(stat -c %a {users}) = 600")
    machine.succeed(f"sha256sum {password} {users} > /tmp/radicale-credentials.sha256")
    machine.succeed(f"printf 'radicale-backup-smoke-7db53f\\n' > {marker}")


def verify():
    machine.succeed(f"grep -Fx 'radicale-backup-smoke-7db53f' {marker}")
    machine.succeed("sha256sum -c /tmp/radicale-credentials.sha256")


def erase():
    machine.succeed("rm -rf /srv/radicale")
    machine.succeed("test ! -e " + password)


ServiceScenario(
    machine,
    units=["radicale.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
