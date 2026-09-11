start_all()
probe = "python /etc/homepage-fixture.py "


def ready():
    machine.wait_for_unit("homepage-dashboard.service")
    machine.wait_for_unit("homepage-truenas-fixture.service")
    machine.wait_until_succeeds(
        "curl -fsS -H 'Host: dashboard.example.test' http://127.0.0.1:22525/site.webmanifest?v=4 | jq -e '.name == \"nixos\"'"
    )


def verify():
    machine.succeed(probe + "verify")
    machine.succeed(
        "grep -F '{{HOMEPAGE_VAR_TRUENASAPIKEY}}' /etc/homepage-dashboard/services.yaml"
    )
    machine.succeed(
        "! grep -F -q -f /run/secrets/homepage/truenasApiKey /etc/homepage-dashboard/services.yaml"
    )


ready()
verify()
