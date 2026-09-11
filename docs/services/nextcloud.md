# Nextcloud

Nextcloud provides file sync, collaboration, and applications. Nixstead runs
the native Nextcloud/PHP stack, listens through a loopback Nginx vhost, and
generates a persistent administrator password during activation.

## Enable and configure

```nix
nixstead.services.productivity.nextcloud = {
  enable = true;
  domain = "nextcloud.home.arpa";
  port = 8083;
  paths.dataDir = "/mnt/appdata/nextcloud-data";
};
```

The data-directory override is optional and does not migrate existing data.
Apps and user storage settings are managed through Nextcloud.

## Initial credentials

The initial username is `admin`. Retrieve the generated or configured password
with the central helper:

```bash
sudo nixstead --host <host> credentials show nextcloud
```

Set `adminPasswordFile` to a service-readable SOPS secret path to choose the
password before activation; otherwise it remains persistently generated at
`/var/lib/nextcloud/nixos-nextcloud-admin-pass`. See
[Secrets and credentials](../secrets.md#find-and-retrieve-credentials).

For Homepage, use Nextcloud's monitoring `NC-Token`, not this password. Inspect
`nextcloud-setup.service` and `phpfpm-nextcloud.service`.

## Dedicated service smokes

`service-nextcloud-recovery` checks the native installed-status endpoint and
writes small markers in the home and data directories. Recovery erases both
directories, runs one shipped Borg restore, and checks readiness and markers.
Dedicated service smokes do not exercise WebDAV workflows, credential failure,
rehearsal, restart/reboot matrices or upgrades.

The reduced clean-restore smoke passed on x86_64-linux with KVM in 75.65
seconds on 2026-09-09, including both directory markers and installed status.

A single `service-nextcloud-recovery` VM covers initial startup/readiness and
one clean backup/restore.
