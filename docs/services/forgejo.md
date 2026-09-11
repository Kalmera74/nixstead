# Forgejo

Forgejo is the preset-selected Git forge. Nixstead runs the native service,
disables public registration, optionally relocates state and repositories, and
idempotently creates the SOPS-defined administrator after startup.

## Enable and configure

```nix
nixstead.services.dev.forgejo = {
  enable = true;
  domain = "forgejo.home.arpa";
  port = 3000;
  paths = {
    stateDir = "/var/lib/forgejo";
    repositoryDir = "/srv/git/repositories";
  };
};
```

Both path overrides are optional and do not migrate existing data. Generate
the initial account with `nixstead --host <host> credentials bootstrap forgejo`.

## Initial credentials

```bash
sudo cat /run/secrets/forgejo/initialAdmin/username
sudo cat /run/secrets/forgejo/initialAdmin/password
```

Open `https://forgejo.home.arpa`. Inspect `forgejo.service` when account
creation or repository access fails.

## Storage and import tuning

Registry backups resolve both the effective state directory and repository root.
A repository root outside the state directory is included separately.

Shared modules retain upstream timeout defaults. Hosts doing unusually large
imports can tune the native interfaces, for example:

```nix
services.forgejo.settings."git.timeout".MIGRATE = 3600;
services.nginx.virtualHosts."forgejo.home.arpa".locations."/".extraConfig = ''
  proxy_read_timeout 3600s;
  proxy_send_timeout 3600s;
'';
```

Existing installations that require longer import or proxy timeouts should keep
those overrides as explicit choices in their consumer host configuration.

## Dedicated startup and recovery smoke

The existing administrator bootstrap passes the runtime password to the native
CLI's `--password` option; the pinned CLI has no password-file or stdin input.
See the [Forgejo 15 CLI](https://forgejo.org/docs/v15.0/admin/command-line/#admin-user-create).
The value remains outside evaluation and derivations, but can be observed in the
short-lived bootstrap process arguments by users permitted to inspect them.
The test's HTTP client reads credentials inside the VM and does not include
them in command arguments or diagnostic output.

The combined `service-forgejo-recovery` startup/restore check runs the
actual native application with its default SQLite engine, a custom state root,
and a separate repository root. Administrator credentials are generated inside
the disposable VM and encrypted before SOPS provisions the real bootstrap unit.
The maintained smoke checks native HTTP readiness and the bootstrapped
administrator, places an independent file marker in each root, then erases both
roots and restores one encrypted Borg archive. Final readiness and marker checks
prove the scoped startup/restore path. Git, issue and attachment workflows,
repeated restart/reboot and archive-failure loops are outside this smoke.

The resolved backup policy follows both native state and repository roots, and
requires the exact native SQLite database filename when it lies inside the
primary application root. A nested repository root is archived once.

These fixtures do not establish recovery for an external database engine,
SQLite files outside the primary root, externally stored attachments or LFS
objects, SSH transport, repository mount-loss fencing, federation, runners, browser interactions, or version
upgrades. Those configurations need their own coordinated backup contract and
runtime evidence. Test definitions alone do not establish a passing run; see the
[implementation status](../service-test-implementation-status.md) for execution
results.

Configuration checks pass on x86_64 and aarch64, including custom native
user/group ownership and custom in-root SQLite filenames. ARM runtime and repository mount-loss fencing remain unverified.

The reduced startup/administrator readiness and one clean marker restore smoke
passed on x86_64 in 120.83 seconds. It contains no Git or issue/attachment workflow.
