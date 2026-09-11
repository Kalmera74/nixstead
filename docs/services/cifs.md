# CIFS client

The CIFS module mounts explicit SMB shares as systemd automounts. It renders a
root-only credentials file from SOPS and applies common UID, media-group, mode,
SMB-version, and `noserverino` settings.

## Enable and configure

```nix
nixstead.services.cifs = {
  enable = true;
  shares.media = {
    source = "//nas/Media";
    mountPoint = "/mnt/media";
    options = ["x-systemd.idle-timeout=60"];
  };
};
```

At least one non-null share is required and mount points must be unique. Set
`uid`, `gid`, `mountOptions`, or `credentialsFile` only when the defaults do not
fit. Generate credentials with `nixstead --host <host> credentials bootstrap cifs`.

## Credentials and operation

The username/password/domain are rendered to `/run/secrets/cifs-credentials`;
applications never receive them directly. Trigger a mount by accessing its
mount point. Inspect the corresponding `.automount` and `.mount` units with
`systemctl` and use `journalctl` for CIFS errors.

## State and recovery boundary

The CIFS client owns mount configuration and runtime credential destinations;
the SMB server owns remote bytes and their recovery. Preserve the encrypted
username/password/domain source and its recipient identity. Reconstruct mounts
from configuration, then obtain credentials at runtime. No independent local
application database is archived for this adapter.

The local-peer fixture uses the native Samba server and actual CIFS
mount units. Each VM generates a separate encrypted SOPS source; only a public
recipient and re-encrypted credentials cross the fixture's shared directory.
The maintained smoke starts the peer and both automounts, installs the generated
runtime credential and reads exact bytes from each share over CIFS. It does not
repeat credential rotation, outages or reboots.

The bounded native-peer startup check passed on `x86_64-linux` in 39.01
seconds. All nine configuration assertions passed on both supported
architectures. The VM preserves the actual CIFS module's filesystem definitions
through QEMU's filesystem override; it does not reconstruct mount options in the
test script. The remote server still owns its stored repository bytes; no test
backs up or repairs the Samba server itself. Credential rotation, outage
handling, upgrades and ARM execution remain unverified by the maintained smoke.
