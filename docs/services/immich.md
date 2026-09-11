# Immich

Immich backs up and manages photos and videos. Nixstead runs the native Immich
server and machine-learning units, creates a local PostgreSQL database, and
uses a dedicated `immich` account plus the media group for the media tree.
It does not require `nixstead.host.user.enable`.

## Enable and configure

```nix
nixstead.services.media.immich = {
  enable = true;
  domain = "immich.home.arpa";
  port = 2283;
  paths.mediaLocation = "/mnt/media/photos/immich";
};
```

The media-location override is optional. Nixstead creates Immich's required
root, subdirectories and marker files but does not move an existing library. The
root is private (`0700`) and belongs to the configured native user and group,
including when a custom root does not exist before the first boot. Configure
external libraries, mobile uploads, jobs, and machine-learning settings in the
application.

## Initial credentials

Open `https://immich.home.arpa`; the first user registered becomes the
administrator. Nixstead does not store the password. Create an API key in
Immich's account settings if Homepage integration is desired.

Inspect `immich-server.service` and `immich-machine-learning.service`.

## Existing identities

Earlier Nixstead revisions ran Immich as `nixstead.host.user.name`. Keep that
identity explicit before updating an existing installation, unless you have
separately migrated its filesystem and database ownership:

```nix
services.immich.user = "existing-photo-owner";
services.immich.database.user = "existing-photo-owner";
```

The account must already be declared in `users.users`. Existing installations
that retain their previous account should keep the override in their consumer
host configuration. New hosts use `immich` by default. Local database
provisioning creates the configured role and database and assigns database
ownership even when their names differ. It does not create an extra database
named after the account or remove previously existing databases. Nixstead
disables upstream `database.createDB` and owns this local provisioning; upstream
still manages extensions and schema setup.

The machine-learning service gives Gunicorn a private runtime directory at
`/run/immich-machine-learning` for its control socket. Home-directory protection
remains enabled. This avoids the control-server permission error when Immich
runs as the host's normal user; ML HTTP ping alone does not check that socket.

## Dedicated startup and recovery smoke

The combined `service-immich-recovery` startup/restore check uses the native
application, a separately declared `photoowner` system account and a custom
`/srv/photos` media root. The smoke checks the native HTTP endpoint and writes an
independent filesystem marker. It performs one clean database/media restore,
then checks readiness and that marker. It creates no accounts, albums or media
uploads, and contains no repeated restart/reboot or detailed failure loops.

Recovery combines the media tree with the selected PostgreSQL database, as
required by [Immich's backup model](https://docs.immich.app/administration/backup-and-restore/).
Nixstead now writes Immich's named database in PostgreSQL custom format as
`database-dumps/immich.dump`. Preflight renders the entire archive through
`pg_restore` without connecting to a database, which detects truncated data even
when its table of contents remains readable. See the
[PostgreSQL archive documentation](https://www.postgresql.org/docs/current/app-pgrestore.html).
The maintained successful path erases the database and media root, restores the
encrypted Borg archive once, and checks readiness and the original marker.

Existing Nixstead Immich archives containing `immich.sql` require a trusted
runtime registry JSON supplied through `NIXSTEAD_REGISTRY_FILE`, with
`immich.backup.databaseFormat` set to `"plain"`. The resolved NixOS registry option
is read-only. Those older archives are not custom archives and must not be
renamed to `.dump`; their legacy path does not gain structural preflight. Keep
the matching media tree with the database and test the older archive separately
before relying on it.

The fixture disables machine learning and external version checks. It does not
establish facial recognition, GPU or ML behavior, external-library recovery,
GPS editing, partner/shared-link workflows, version upgrades, or preflight detection of a
single missing media file inside an otherwise present archive directory.
Exact execution results are recorded in the
[implementation status](../service-test-implementation-status.md).

The maintained x86_64 clean database/media restore smoke passed in
**284.50 seconds**, including final native HTTP readiness and the original file
marker. Initial and restored startup emitted the same upstream geodata-index
schema warnings; geographic search is outside this smoke.

The configuration check built on x86_64 and evaluated on aarch64; no ARM runtime coverage is claimed.
