# Actual Budget

Actual Budget is a privacy-focused personal finance server. Nixstead runs the
native `actual.service` and stores its state in `/var/lib/actual`.

## Enable and configure

```nix
nixstead.services.productivity.actualbudget = {
  enable = true;
  domain = "budget.home.arpa";
  port = 8189;
};
```

The repository path option defaults to the fixed `/var/lib/actual` location.
Native `services.actual.settings` overrides remain supported: `dataDir` holds
the migration journal, `serverFiles` holds authentication and the file catalogue,
and `userFiles` holds budget blobs and synchronization databases. Budget files,
synchronization, and optional bank-sync settings are managed in the application.

## Initial credentials

Open `https://budget.home.arpa` and set the server password through Actual's
first-run interface. There is no repository-generated username or password.
Keep the server password and any encryption keys in a password manager. Inspect
`actual.service` and `journalctl -u actual`.

## State and recovery boundary

The registry follows all three effective native state paths and removes nested
duplicates. A separate `userFiles` or `serverFiles` directory gets its own archive
slot. Recovery must retain the `.migrate` journal, `account.sqlite`, budget blobs
and their synchronization databases together. The journal is checked as strict
JSON before a restore can stop the service or change live state. An account
database inside the primary state root is required by its exact relative path;
each separate archive slot must also exist.

The default native service uses `DynamicUser` and a private systemd state
directory. Its restore ownership falls back to root until systemd prepares that
directory for the service. With a named native `services.actual.user` and
`services.actual.group`, the restore follows those configured identities. A host
that overrides native paths must also provision the named account and writable
directories. The service waits for mounts containing all three native paths.

## Service checks

The x86_64 smoke fixtures start the pinned native service, bootstrap its server
password, and check the health endpoint and original administrator token. A
small fixture marker in each effective native state directory makes missing
backup paths visible without exercising budget internals.

The recovery checks cover both the default private `DynamicUser` directory and
a named account with separate budget storage. They create an encrypted Borg
backup, erase the original backing bytes, restore it with the shipped command,
and require service readiness, the original token and the marker bytes. Each
profile performs one clean restore; there are no repeated reboot loops.

Configuration assertions cover custom paths, listener/exposure settings, native
account selection and required recovery inputs on both architectures. Budget
editing, transaction synchronization, bank feeds, OIDC, end-to-end encryption,
corruption matrices and ARM runtime are outside this smoke contract.

The x86_64 startup and clean Borg restore checks passed in 98.77 seconds for
the custom named-account profile and 72.74 seconds for the default `DynamicUser`
profile. Configuration assertions passed on x86_64 and aarch64; this host has
no ARM builder, so the ARM configuration derivation was evaluated without
realization.
