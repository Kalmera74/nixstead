# Seerr

Seerr provides media discovery and requests in front of Jellyfin and the
ARR applications. Nixstead uses the native Seerr service and exposes it through
the registry endpoint.

## Enable and configure

```nix
nixstead.services.media.seerr = {
  enable = true;
  domain = "want.home.arpa";
  port = 5055;
};
```

Open `https://want.home.arpa` and complete administrator onboarding. Relationships
can then be managed through `seerr.integrations`; see the example below.

## Initial credentials

There is no separate repository-generated password. Initial access uses the
Jellyfin account selected during onboarding. When shared credentials are enabled,
automatic enrollment saves and delivers the canonical `seerr/apiKey` before
startup. It reuses an existing SOPS key or imports the native key; a fresh instance
receives a key generated and saved in SOPS first. Seerr and its consumers receive
the same value. Administrator onboarding remains required. See
[credential operations](../media-operations.md#canonical-sops-credentials).

Inspect `seerr.service` with `systemctl status seerr` and `journalctl -u seerr`.

## Canonical state and backups

The module explicitly selects `services.seerr.stateRevision = 1`, independently
of the host's existing `system.stateVersion`. The default configuration path is
`/var/lib/seerr`. `nixstead.services.media.seerr.paths.configDir` supplies a typed
default; an explicit native `services.seerr.configDir` override becomes the
effective path used by systemd and backups. Paths must be normalized below
`/var/lib`; systemd itself handles `/var/lib/private` for the dynamic user.

Backups use the effective native configuration directory and the identifier
`seerr`. Both `settings.json` and a populated `db/db.sqlite3` are required.
Missing required state fails backup/restore preflight explicitly. Restore into a
clean instance prepares private state and lets systemd create its public mapping
and assign the new dynamic UID. The dedicated VM checks restore an independent state-file marker from Borg
and verify native readiness after restored startup.

The default local SQLite policy additionally parses `settings.json` as strict
JSON and runs SQLite `quick_check` against a private copy of the staged database.
Missing, empty or malformed input is rejected before restore stops the live
service. The SQLite integrity profile requires a cleanly stopped, checkpointed
database: nonempty WAL or rollback-journal companions are explicitly refused.
This is a structural file check, not an application-schema migration validator.
Native Seerr leaves a committed WAL when terminated, so the module checkpoints
the existing native SQLite database after its process exits. A failed or busy
checkpoint fails the stop operation; a missing database is never created by this
hook. Runtime `DB_TYPE=postgres` bypasses the SQLite hook and remains outside
this local SQLite recovery profile.

## Dedicated startup and recovery smoke

The checks run native Seerr 3.4.1 under canonical state revision 1 with an older
host stateVersion. They check HTTP readiness, write an independent state-file
marker, erase the public/private application state, and restore one encrypted
Borg archive. Final readiness and the original marker establish the scoped
startup/restore path. The smoke has no account/request workflows, external
metadata/bootstrap peers, repeated reboots or detailed failure cases.

The reduced native startup and one clean state-marker restore smoke passed in
100.36 seconds on x86_64.

Configuration checks passed for x86_64 and aarch64; ARM runtime remains
unverified. See the
[implementation status](../service-test-implementation-status.md) for execution
evidence.

## Existing connections after exposure changes

Nixstead can keep existing Seerr server connections aligned with the enabled
native ARR applications without taking over request policy:

```nix
nixstead.services.media.seerr.integrations = {
  enable = true;
  destinations.sonarr.existingServer = {};
  destinations.radarr.existingServer = {};
};
```

This explicitly selects connection management and enables shared runtime
credentials. The reconciler sets the hostname,
port, SSL flag, base URL and API key from registry endpoints and runtime key
sources. For native services on the same host the endpoint uses `127.0.0.1`,
the configured ARR port and HTTP. API keys are never embedded in Nix values.
Names, quality profiles, root folders, tags, defaults, 4K selections and request
settings stay managed in Seerr. Do not supply `qualityProfileId` or `rootFolder`
alongside `existingServer`.

An empty selector requires exactly one existing server of that application type
on the first run. With multiple servers, select one explicitly using
`existingServer.id = 0` or `existingServer.name = "My server"` (or both). The
ownership journal binds that selection to its ID before writing. Later servers
remain untouched. A missing recorded server or changed selector fails explicitly;
it does not silently select a replacement or create an entry. Disabling the
destination stops management without deleting it.

Every reconciliation run tests the target through Seerr and validates that the
current selected profile and root folder exist. Changed connection fields are
saved through Seerr's API, read back and tested again. Reconciliation runs on
startup, configuration/key changes and periodically; inspect it with
`sudo nixstead-status` or `journalctl -u nixstead-arr-reconcile`. Set
`nixstead.services.arr.integrations.dryRun = true` to inspect redacted proposed
changes without saving them. The ARR stack alone does not enable this behavior.
The reconciler is a oneshot service: `ActiveState=inactive` with `Result=success`
is expected after it finishes. Its timer remains active between runs. An empty
`changes` list with `success: true` means validation passed without further edits.

Seerr's own status endpoint and Nginx availability do not validate its saved
connections. If automatic management is disabled, use **Test** and **Save** under
**Settings → Services** after editing the server addresses. Isolated containers
and VPN namespaces require endpoints reachable from their own network context;
their loopback address does not refer to the host.

## Selected relationships

Import the ARR and media modules and enable the participating services:

```nix
nixstead.services.media.seerr.integrations = {
  enable = true;
  jellyfin = {
    # Enabled by default when Jellyfin and Seerr integrations are enabled.
    libraryPolicy = "auto";
  };
  destinations.sonarr = {
    qualityProfileId = 1; # choose an existing profile explicitly
    rootFolder = "/mnt/media/data/media/tv";
    isDefault = false;
    searchOnRequest = false;
  };
};
```

The Jellyfin connection uses the registry's internal endpoint and the same
`homepage/jellyfinApiKey` SOPS entry as Homepage. No library IDs or key-file path
are needed. This secret is also declared when Homepage is disabled, delivered
through `LoadCredential`, and restarts the reconciler on SOPS deployment changes.
Supply a valid **Jellyfin-issued** key with access to its libraries in that SOPS
entry; Nixstead cannot generate arbitrary keys that Jellyfin will accept. Complete
Jellyfin and Seerr administrator onboarding before reconciliation. This feature
does not create administrator accounts, Jellyfin libraries or media files.

`jellyfin.libraryPolicy` controls selection:

| Policy | Behavior |
| --- | --- |
| `auto` (default) | Preserve an existing Seerr library list's selections. If the list is empty, discover and enable movie and TV libraries once. |
| `preserve` | Preserve current choices; newly discovered libraries start disabled, including on an empty instance. |
| `movies-and-tv` | Enable every discovered movie and TV library on each run, including newly added libraries and UI drift. |
| `explicit` | Enable the IDs in `jellyfin.libraries`; setting a nonempty list selects this policy by default. |

Every policy preserves other enabled libraries. Mixed libraries are available
for explicit or UI selection but are not selected automatically. An existing
list with every library disabled stays disabled under `auto`; it is not treated
as a fresh installation. Later library additions are discovered but remain
disabled under `auto` and `preserve`. Use `movies-and-tv` to enable future movie
and TV libraries automatically. Disabling `jellyfin.enable` stops management.

Discovery uses Jellyfin's read-only API on every run, including dry runs.
Seerr's mutating library refresh receives the complete intended selection, so
renaming a library does not reset its enabled state. Empty or malformed discovery,
invalid credentials, unavailable explicit selections, and missing previously
enabled libraries fail before changes are written. Inspect those failures with
`sudo nixstead-status`; for a deliberately removed library, remove its selection
in Seerr before retrying. Concurrent UI edits detected before saving defer the
update to the next run. Upstream provides no conditional-write API, so a UI edit
in the final interval between the check and the save cannot be made atomic.

For an externally managed runtime key, `jellyfin.apiKeyFile` remains available;
it overrides automatic SOPS selection. Keep that file restricted and manage its
rotation explicitly. The periodic reconciler reads it afresh. Discovery policies
must leave `jellyfin.libraries` empty to avoid conflicting selection rules.

Destination profile IDs and roots are validated against the application API.
A conflicting existing default is rejected; unowned destination fields remain
unchanged. The ensure-only ownership journal protects created destinations.
