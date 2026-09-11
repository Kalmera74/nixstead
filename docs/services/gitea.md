# Gitea

Gitea is an alternative Git forge. Nixstead runs the native service, disables
public registration, optionally relocates state, and creates the encrypted
initial administrator after startup.

## Enable and configure

```nix
nixstead.services.dev = {
  forgejo.enable = false;
  gitea = {
    enable = true;
    domain = "gitea.home.arpa";
    port = 3002;
    paths.stateDir = "/var/lib/gitea";
  };
};
```

Generate the account with `nixstead --host <host> credentials bootstrap gitea`.

## Initial credentials

```bash
sudo cat /run/secrets/gitea/initialAdmin/username
sudo cat /run/secrets/gitea/initialAdmin/password
```

Open `https://gitea.home.arpa`. Homepage uses a separate API token created from
the user's **Settings > Applications** page. Inspect `gitea.service`.

## Dedicated startup and recovery smoke

The existing administrator bootstrap passes the runtime password to the native
CLI's `--password` option; the pinned CLI has no password-file or stdin input.
See the [Gitea 1.27.3 CLI source](https://github.com/go-gitea/gitea/blob/v1.27.3/cmd/admin_user_create.go).
The value remains outside evaluation and derivations, but can be observed in the
short-lived bootstrap process arguments by users permitted to inspect them.
The test's HTTP client reads credentials inside the VM and does not include
them in command arguments or diagnostic output.

The combined `service-gitea-recovery` startup/restore check runs the
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

Configuration checks passed for both x86_64 and aarch64; application VM
execution on aarch64 remains unverified.

The reduced startup/administrator readiness and one clean marker restore smoke
passed on x86_64 in 169.25 seconds. It contains no Git or issue/attachment workflow.
