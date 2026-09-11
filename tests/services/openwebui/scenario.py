from datetime import timedelta

markers = ["/var/lib/open-webui/.nixstead-smoke-marker"]


def ready():
    machine.wait_for_unit("open-webui.service", timeout=timedelta(seconds=600))
    machine.wait_until_succeeds(
        "curl -fsSL --max-time 5 http://127.0.0.1:28081/health >/dev/null",
        timeout=timedelta(seconds=600),
    )


def populate():
    for marker in markers:
        machine.succeed("printf 'openwebui-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    for marker in markers:
        machine.succeed("grep -Fx 'openwebui-backup-smoke-9f4c7a' " + marker)


def erase():
    machine.succeed("rm -rf /var/lib/open-webui /var/lib/private/open-webui")
    machine.succeed(
        "test ! -e /var/lib/open-webui && test ! -e /var/lib/private/open-webui"
    )


ServiceScenario(
    machine,
    units=["open-webui.service"],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
