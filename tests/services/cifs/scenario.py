start_all()
server.wait_for_unit("samba-smbd.service")
client.wait_for_unit("mnt-rw.automount")
client.wait_for_unit("mnt-readonly.automount")
server.succeed(
    "printf 'Remote original bytes 0123456789\n' > /srv/cifs-peer-writable/original; cp /srv/cifs-peer-writable/original /srv/cifs-peer-readonly/original; chown fixture-smb:users /srv/cifs-peer-writable/original /srv/cifs-peer-readonly/original"
)

# The two disposable machines generate separate encrypted fixtures. Transfer the
# server credential into the client source, activate it, and exercise each mount
# once. Configuration assertions cover invalid and conflicting declarations.
client.succeed(
    "age-keygen -y /var/lib/service-fixture/identity > /tmp/shared/cifs-client-recipient"
)
server.succeed("python /etc/cifs-credentials-fixture.py export")
client.succeed(
    "install -m 0600 /tmp/shared/cifs-client-source.yaml /var/lib/service-fixture/secrets.yaml; /run/current-system/activate > /dev/null"
)
client.succeed(
    "systemctl reset-failed mnt-rw.mount mnt-readonly.mount; systemctl restart mnt-rw.automount mnt-readonly.automount"
)
client.wait_until_succeeds(
    "timeout 10 grep -Fx 'Remote original bytes 0123456789' /mnt/rw/original",
    timeout=90,
)
client.succeed("grep -Fx 'Remote original bytes 0123456789' /mnt/readonly/original")
client.succeed(
    "findmnt --mountpoint /mnt/rw --noheadings --types cifs; findmnt --mountpoint /mnt/readonly --noheadings --types cifs"
)
