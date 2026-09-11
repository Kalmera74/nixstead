start_all()
machine.wait_for_unit("pihole-api-fixture.service")
machine.wait_for_unit("nixstead-pihole-dns-sync.service")
machine.succeed("python /etc/pihole-fixture.py verify")
