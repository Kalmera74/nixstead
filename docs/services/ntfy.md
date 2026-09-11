# ntfy

ntfy is a push-notification server. Nixstead runs the native `ntfy-sh.service`
with deny-by-default topic access and generates a persistent administrator
password locally before first startup.

## Enable and configure

```nix
nixstead.services.dev.ntfy = {
  enable = true;
  domain = "ntfy.home.arpa";
  port = 2586;
  adminUsername = "admin";
};
```

The fixed state directory is `/var/lib/ntfy-sh`; it contains messages,
attachments, the auth database, and bootstrap credential files.

## Initial credentials

Retrieve the configured username and generated or configured password with:

```bash
sudo nixstead --host <host> credentials show ntfy
```

Set `adminPasswordFile` to a SOPS secret path to choose the password before
activation; otherwise `/var/lib/ntfy-sh/admin-password` is generated. See
[Secrets and credentials](../secrets.md#find-and-retrieve-credentials).

Inspect `ntfy-bootstrap-credentials.service` and `ntfy-sh.service`.
Both units share the native private state directory and service identity.
An external password is loaded through systemd credentials, so its source can
remain root-readable while the bootstrap runs as the service user.

## State and recovery boundary

The registry archive owns the entire `/var/lib/ntfy-sh` directory. Stop the
native service before staging its SQLite account/ACL database (`user.db`),
retained-message database (`cache.db`), local `attachments` directory and
generated administrator credential. The generated `auth.env` is also included;
bootstrap can derive it again from the original password. Restoring into an empty
directory follows the native systemd `DynamicUser` state-directory handling.

Recovery requires populated account and message databases. When
`adminPasswordFile` is unset it also requires the original `admin-password`;
missing any of these inputs makes the restore helper refuse before stopping the
healthy service or changing its files. A configured external password file is
owned by its encrypted source, with the recipient identity backed up separately.
It is not silently copied into the service archive or replaced by a generated
password. Keep the original source available when restoring this profile.

Accounts and topic ACLs created with the native CLI are application state. The
administrator bootstrap does not reconstruct additional users. The dedicated
smoke checks native HTTP health and a small state-file marker. Recovery erases
the native state root, runs one shipped Borg restore, and checks health and the
marker. Publish/subscribe workflows, topic ACL matrices, attachment delivery,
expiry, remote push and restart/reboot loops are outside the maintained smoke.

All 29 configuration assertions pass on both architectures. External database/storage, explicit password override, upgrades
and ARM application execution remain unverified.

## Optional operational integration

See [media operations](../media-operations.md) for runtime credential sharing,
selected API relationships and storage permissions, and the
[support matrix](../support-matrix.md) for tested behavior. These features require
explicit selection; enabling a service alone does not perform API reconciliation.

The reduced clean-restore smoke passed on x86_64-linux with KVM in 40.32
seconds on 2026-09-09. This timing covers startup, one marker and one shipped
Borg backup/restore.

A single `service-ntfy-recovery` VM covers initial startup/readiness and
one clean backup/restore.
