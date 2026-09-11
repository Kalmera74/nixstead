# n8n

n8n builds event-driven automations and workflows. Nixstead runs the native
`n8n.service`, configures secure-cookie behavior, and publishes webhooks using
the service domain.

## Enable and configure

```nix
nixstead.services.productivity.n8n = {
  enable = true;
  domain = "n8n.home.arpa";
  port = 5678;
};
```

Credentials for external systems, workflows, triggers, and encryption state are
stored by n8n itself. Back up service state before upgrades or path changes.

## Initial credentials

Open `https://n8n.home.arpa` and complete the owner-account setup. Nixstead
does not preseed the owner email or password. Inspect `n8n.service` and verify
that external webhook URLs resolve to the configured domain.

## State and recovery

The native unit owns `/var/lib/n8n`; n8n stores its default SQLite database,
workflow and execution records, owner account, encrypted credentials, and
`config` encryption material in the `.n8n` subdirectory. The backup stops the
native unit and snapshots this directory. Restoring just a workflow export or
the database without the original encryption material does not restore usable
credentials.

The native service uses a dynamic system account. Restore stages files with
root ownership; systemd assigns the service identity and fixes its state
directory ownership when the unit starts.

The shipped recovery tools require a populated `.n8n/config` with a nonempty
`encryptionKey` string. For the visible native default SQLite profile they also
require `.n8n/database.sqlite`. The complete stopped directory is archived,
including SQLite WAL and shared-memory companions when present. Native n8n can
retain a WAL after a clean shutdown, so the backup must preserve that bundle
rather than requiring a standalone checkpointed database. Config validation
checks required encryption material without printing its value; it does not
prove every n8n schema or encryption-key/database relationship.

A native `services.n8n.environment.N8N_ENCRYPTION_KEY_FILE` override uses a
systemd runtime credential. n8n still writes its encryption material into its
native config, and both the original runtime secret source and native state
must be retained consistently. Recovery does not rotate the encryption key.
A custom SQLite filename, external PostgreSQL selection, or runtime-only
database configuration omits the assumed default database check; operators
must separately cover that effective database and its coherent recovery.
External side effects, remote systems, and their credentials' validity remain
outside the local archive.

## Dedicated checks

`service-n8n-config` checks isolated selection, the actual native listener,
exposure, proxy/card behavior, secure cookies, runtime credential wiring, and
conditional backup requirements on x86-64 and AArch64 evaluation. The wrapper
sets `N8N_LISTEN_ADDRESS` as well as n8n's advertised URL host, so private
exposure actually binds the loopback interface.

`service-n8n-recovery` starts native n8n 2.36.7 with its default SQLite profile
and checks HTTP readiness on the configured private listener. The fixture
turns off unused browser asset generation and limits Node memory. Its package
uses the pinned native source and production build with lower local build
parallelism.

The same VM then checks that the shipped backup and encrypted Borg restore
complete, including startup after deleting both the public DynamicUser state
path and its private backing directory. A small state marker and the original
encryption identity must survive the restore. This is a service wiring and
backup completion check; it does not test workflow internals, usable external
credentials, browser behavior, third-party integrations, queue workers,
external database recovery, AArch64 runtime, or cross-version upgrades.

A single `service-n8n-recovery` VM covers initial startup/readiness and
one clean backup/restore.
