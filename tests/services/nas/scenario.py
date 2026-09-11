start_all()
machine.wait_for_unit("srv-pool.mount")
for mount_point in ["/mnt/data1", "/mnt/data2", "/mnt/parity"]:
    machine.succeed(
        "findmnt --mountpoint " + mount_point + " --noheadings --types ext4"
    )
machine.succeed("findmnt --mountpoint /srv/pool --noheadings --types fuse.mergerfs")

# One real write verifies that the configured pool is usable. Parity maintenance
# and repair are independent operational jobs, not service-start assertions.
machine.succeed("systemctl start nas-fixture-writer.service")
machine.succeed("python /etc/nas-fixture-probe.py populate")
machine.succeed("python /etc/nas-fixture-probe.py verify")
