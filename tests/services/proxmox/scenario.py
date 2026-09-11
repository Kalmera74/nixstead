start_all()
machine.wait_for_unit("homepage-dashboard.service")
machine.wait_for_unit("homepage-proxmox-fixture.service")
machine.wait_until_succeeds(
    "curl -fsS -H 'Host: dashboard.example.test' http://127.0.0.1:22526/site.webmanifest?v=4 | jq -e '.name == \"nixos\"'"
)
machine.succeed("python /etc/proxmox-fixture.py verify")
