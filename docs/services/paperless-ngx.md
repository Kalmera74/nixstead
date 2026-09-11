# Paperless-ngx

Paperless-ngx consumes documents, performs OCR, and builds a searchable archive.
Nixstead runs the native web, consumer, task-queue, and scheduler units with a
local PostgreSQL database and a runtime-generated application secret.

## Enable and configure

```nix
nixstead.services.productivity.paperless = {
  enable = true;
  domain = "paperless.home.arpa";
  port = 28981;
  paths = {
    dataDir = "/var/lib/paperless";
    mediaDir = "/mnt/documents/paperless";
    consumeDir = "/mnt/documents/inbox";
  };
};
```

All path overrides are optional. Dropping a file into `consumeDir` starts the
ingestion workflow. Paths on network storage must support the access and
locking behavior described in the storage guide.

## Initial credentials

Nixstead does not generate a Paperless login. Create the first administrator
on the host with `sudo -u paperless paperless-manage createsuperuser`, then open
`https://paperless.home.arpa`. Create the optional Homepage API token from the
user profile. Inspect `paperless-web.service` and `paperless-consumer.service`.

The native `paperless-secret-key.service` owns the application secret. It
generates `nixos-paperless-secret-key.env` in the effective data directory and
reuses a legacy value-only key on the first upgrade. Nixstead no longer generates
a second key during web startup. To supply a key explicitly, use a
service-readable runtime `services.paperless.environmentFile`, such as an SOPS
template. The manual `paperless-secret` helper only preseeds the legacy file
before first startup and refuses once an active environment file exists.
When using the configured destination, run it as root or the configured
Paperless account; the helper assigns the file to that account with mode 0600.
An explicit output path creates a caller-owned export for manual provisioning.
Preseed values allow letters, digits, underscores and hyphens so the native
legacy conversion preserves them safely; use `environmentFile` for other values.

Backups include the effective data directory plus separate document and inbox
directories. Paths already inside the data directory are covered by that
snapshot. After enabling separate directories, take a new full backup; older
archives may lack those documents.

## Dedicated service smokes

The combined smoke starts the native application and dependencies, checks HTTP
readiness, and writes small markers in the separate data, document and inbox
directories. Recovery erases those directories and the local database, runs one
shipped Borg restore, and checks readiness and all markers. Ingestion, OCR,
search, credential-failure and restart/reboot matrices are outside this smoke.

The reduced clean-restore smoke passed on x86_64-linux with KVM in 373.08
seconds on 2026-09-09. Native startup and database setup dominate this run;
no document ingestion or OCR operation is part of the timing.

A single `service-paperless-recovery` VM covers initial startup/readiness and
one clean backup/restore.
