# Linkwarden

Linkwarden archives and organizes bookmarks. Nixstead runs digest-pinned
Linkwarden, PostgreSQL, and Meilisearch containers with separate persistent
state directories.

## Enable and configure

```nix
nixstead.services.productivity.linkwarden = {
  enable = true;
  domain = "linkwarden.home.arpa";
  port = 8186;
  paths.dataDir = "/var/lib/linkwarden";
};
```

Generate the application, database, and search secrets with
`nixstead --host <host> credentials bootstrap linkwarden`. Registration is enabled by
the current module so the first account can be created.

## Initial credentials

Open `https://linkwarden.home.arpa` and register the first user. Nixstead does
not store that password. Create a separate access token under
**Settings > Access Tokens** for Homepage. Inspect `docker-linkwarden.service`
and its database and Meilisearch companion units.

## Backup and smoke scope

The registry owns the entire configured `paths.dataDir`, including application captures, PostgreSQL data and Meilisearch state.
The shipped backup coordinates the three containers and includes a logical
PostgreSQL dump. Restore uses the same pinned profile and the original runtime
SOPS credentials. Keep the encrypted source and its recipient identity
separately; they are not part of this application archive.

The dedicated combined smoke loads the pinned application/dependency images,
generates disposable encrypted runtime credentials, and checks application HTTP
readiness. Its VM has four CPUs to satisfy the application's configured
container CPU limit. Recovery writes a small file marker, erases the owned state root,
runs one shipped encrypted Borg restore and checks readiness and the marker.
Business workflows, search/queue correctness, failures, restart/reboot matrices,
upgrades and ARM application execution are outside this smoke.

All 29 configuration assertions passed on x86_64-linux and aarch64-linux.

A single `service-linkwarden-recovery` VM covers initial startup/readiness and
one clean backup/restore.

The combined check passed on x86_64-linux with KVM in 349.20 seconds on
2026-09-09. The timing includes loading the exact supported images, initial
HTTP readiness, the shipped PostgreSQL/Borg backup and clean restore, and final
HTTP readiness with the original file marker.
