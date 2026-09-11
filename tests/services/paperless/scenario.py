from datetime import timedelta

markers = [
    "/srv/paperless-data/.nixstead-smoke-marker",
    "/srv/paperless-documents/.nixstead-smoke-marker",
    "/srv/paperless-inbox/.nixstead-smoke-marker",
]


def ready():
    machine.wait_for_unit("paperless-web.service", timeout=timedelta(seconds=600))
    machine.wait_until_succeeds(
        "curl -fsSL --max-time 5 http://127.0.0.1:28982/ >/dev/null",
        timeout=timedelta(seconds=600),
    )


def populate():
    for marker in markers:
        machine.succeed("printf 'paperless-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    for marker in markers:
        machine.succeed("grep -Fx 'paperless-backup-smoke-9f4c7a' " + marker)


def erase():
    machine.succeed("runuser -u postgres -- dropdb paperless")
    machine.succeed(
        "rm -rf /srv/paperless-data /srv/paperless-documents /srv/paperless-inbox"
    )
    machine.succeed(
        "test ! -e /srv/paperless-data && test ! -e /srv/paperless-documents && test ! -e /srv/paperless-inbox"
    )


ServiceScenario(
    machine,
    units=[
        "paperless-web.service",
        "paperless-consumer.service",
        "paperless-scheduler.service",
        "paperless-task-queue.service",
    ],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
