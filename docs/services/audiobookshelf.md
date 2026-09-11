# Audiobookshelf

Audiobookshelf manages and streams audiobooks and podcasts. Nixstead runs the
native `audiobookshelf.service` on the registry-managed listener.

## Enable and configure

```nix
nixstead.services.media.audiobookshelf = {
  enable = true;
  domain = "audiobookshelf.home.arpa";
  port = 13378;
  paths.dataDir = "/var/lib/audiobookshelf-custom";
};
```

The data-directory override is optional but, when set, must be a directory
strictly below `/var/lib`. Library paths, metadata providers, podcasts, and
users are configured in the web UI.

## Initial credentials

Open `https://audiobookshelf.home.arpa`; the first account created during setup
is the administrator. Nixstead does not store its password. A user's API token
for Homepage is available from that user's configuration.

Inspect it with `systemctl status audiobookshelf` and
`journalctl -u audiobookshelf`.

## State backup and smoke check

Backups follow the native service's effective working directory below `/var/lib`,
including its configuration and metadata. Native user/group overrides also
select restore ownership, and service startup waits for that state mount.
Library source files are separately owned and need a separate backup.

The x86_64 smoke uses a custom application path, waits for native HTTP readiness,
writes one explicit state marker, and performs one clean encrypted Borg restore.
It checks readiness and marker bytes after restore. It does not exercise library
scans, playback, progress, source-content recovery, repeated reboots or detailed
failure cases. ARM configuration checks do not establish ARM runtime support.

The x86_64 startup and clean restore smoke passed in 47.31 seconds. Configuration
assertions built on x86_64 and evaluated on aarch64; no ARM builder is available
on this host.
