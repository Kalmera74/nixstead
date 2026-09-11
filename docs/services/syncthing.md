# Syncthing

Syncthing continuously synchronizes folders between trusted devices. Nixstead
runs the native service, generates a local GUI password, exposes the GUI through
Nginx, and opens only the configured transfer/discovery ports according to
registry policy.

## Enable and configure

```nix
nixstead.services.syncthing = {
  enable = true;
  domain = "syncthing.home.arpa";
  port = 8384;
  transferPort = 22000;
  discoveryPort = 21027;
  user = "syncthing";
  group = "syncthing";
  paths = {
    dataDir = "/var/lib/syncthing";
    configDir = "/var/lib/syncthing/.config/syncthing";
  };
};
```

The reverse proxy deliberately sends `Host: localhost` to satisfy Syncthing's
host check. Devices and folders remain application-managed because override is
disabled.

## Initial credentials

Retrieve the configured GUI username and generated or configured password with:

```bash
sudo nixstead --host <host> credentials show syncthing
```

Set `guiPasswordFile` to a Syncthing-readable SOPS secret path to choose the
password before activation; otherwise the password remains locally generated.
See [Secrets and credentials](../secrets.md#find-and-retrieve-credentials).

Inspect `syncthing-bootstrap-password.service` and `syncthing.service`.

## State and recovery boundary

The registry archive owns `paths.configDir`: device certificate/key, configuration,
indexes and the generated GUI credential. The application must stop before this
state is staged. A configured external GUI-password file is recovered from its
encrypted source, with the original recipient identity kept separately.

The stopped-service archive must contain populated `config.xml`, `cert.pem`
and `key.pem`. When `guiPasswordFile` is unset, it must also contain the original
generated `gui-password`; otherwise bootstrap would silently rotate the GUI
credential. An explicit external password remains owned by its encrypted source.
The restore helper rejects an archive missing any required input before
changing live state. A clean configuration directory is restored with the
effective native Syncthing user/group, including custom identities. The index
inside that directory belongs to the same snapshot; losing it can change local
file-version history even when the folder bytes remain available elsewhere.

Synced folder bytes have a separate storage owner; folders can reside outside
both `configDir` and `dataDir`. List each owned folder in that owner's independent
backup policy. Propagated deletion and synchronization are not a backup, and a
peer's surviving copy does not establish independent backup recovery.

The dedicated service smoke starts one native daemon, checks GUI HTTP readiness,
and writes a small marker inside `configDir`. Recovery erases only that directory,
runs one shipped Borg restore and checks readiness and the marker. It does not
enroll a peer or exercise synchronization, version vectors, conflict handling,
credential denial or repeated lifecycle checks. Synced bytes remain separately
owned and no independent synced-file backup is claimed.

Configuration checks pass on both architectures; upgrades and ARM runtime remain unverified.

The reduced clean-restore smoke passed on x86_64-linux with KVM in 39.73
seconds on 2026-09-09. This timing covers startup, one marker and one shipped
Borg backup/restore.

A single `service-syncthing-recovery` VM covers initial startup/readiness and
one clean backup/restore.
