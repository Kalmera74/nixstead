from datetime import timedelta

markers = [
    "/srv/nextcloud-data/.nixstead-smoke-marker",
    "/srv/nextcloud-home/.nixstead-smoke-marker",
]


def ready():
    machine.wait_for_unit("nextcloud-cron.timer", timeout=timedelta(seconds=600))
    machine.wait_until_succeeds(
        "curl -fsSL --max-time 5 --header 'Host: nextcloud.home.arpa' http://127.0.0.1:28083/status.php | jq -e .installed",
        timeout=timedelta(seconds=600),
    )


def populate():
    for marker in markers:
        machine.succeed("printf 'nextcloud-backup-smoke-9f4c7a\\n' > " + marker)


def verify():
    for marker in markers:
        machine.succeed("grep -Fx 'nextcloud-backup-smoke-9f4c7a' " + marker)


def erase():
    machine.succeed("rm -rf /srv/nextcloud-data /srv/nextcloud-home")
    machine.succeed("test ! -e /srv/nextcloud-data && test ! -e /srv/nextcloud-home")


ServiceScenario(
    machine,
    units=[
        "nextcloud-cron.timer",
        "nextcloud-cron.service",
        "phpfpm-nextcloud.service",
    ],
    ready=ready,
    populate=populate,
    verify=verify,
    erase=erase,
).run(phase)
