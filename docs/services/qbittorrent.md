# qBittorrent

qBittorrent is the ARR download client. Nixstead runs the native
`qbittorrent.service`, applies the Web UI listener, and installs SOPS-managed
credentials into qBittorrent's configuration before startup.

## Enable and configure

```nix
nixstead.services.arr.qbittorrent = {
  enable = true;
  domain = "bit.home.arpa";
  port = 8080;
  paths = {
    savePath = "/mnt/media/data/torrents/";
    tempPath = "/mnt/media/data/torrents/temp/";
  };
};
```

Automatic enrollment reuses existing SOPS credentials or saves a username (`arr`)
and random password before first startup. The host needs its enrolled SOPS
identity and writable encrypted source; see [credential operations](../media-operations.md#canonical-sops-credentials).

## Initial access and credentials

Open `https://bit.home.arpa`. The canonical username and password are stored at
`qbittorrent/username` and `qbittorrent/password` in the host's encrypted SOPS
document. The runtime broker delivers them through restricted files and systemd
credentials; qBittorrent's startup helper derives the native PBKDF2 hash.
Homepage and selected integrations receive the same deployed credentials.

During startup or a rebuild, reconciliation waits for the WebUI login page before
authenticating. A running systemd unit can still be restoring its torrent session.
Readiness retries are bounded; invalid credentials fail without repeated login
attempts. Check `sudo nixstead-status` for the result and subsequent timer retries.

Recover the plaintext value from the encrypted host file when necessary:

```bash
nixstead --host <host> credentials show qbittorrent
```

To rotate the password, run `nixstead --host <host> credentials rotate
qbittorrent`. Automatic refresh delivers it within about a minute and restarts
affected consumers. With `arr.credentials.autoSync.enable = false`, enroll
credentials manually and rebuild to deliver them.

Inspect it with `systemctl status qbittorrent` and
`journalctl -u qbittorrent`.

## Optional operational integration

See [media operations](../media-operations.md) for runtime credential sharing,
selected API relationships and storage permissions, and the
[support matrix](../support-matrix.md) for tested behavior. These features require
explicit selection; enabling a service alone does not perform API reconciliation.

## Dedicated smoke checks

The x86_64 service checks share one combined native ARR startup/recovery
fixture, so selecting several family members reuses one VM derivation.
They check service readiness, private runtime SOPS credentials, and one selected
shipped reconciliation. Stateful services get one encrypted Borg backup and
empty-state restore, followed by readiness and an independent file marker in
each selected metadata root. Media acquisition/import, existing queues and
libraries, repeated lifecycle, and incomplete-input matrices are outside this
fixture. Source and download bytes remain separately owned.

The combined x86_64 startup/recovery check passed in 641.19 seconds in the
recorded run. Configuration is checked independently for each service on x86_64
and aarch64.
