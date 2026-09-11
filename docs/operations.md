# Operations and troubleshooting

This guide covers routine evaluation, activation, health checks, updates, and
failure diagnosis. Commands assume the repository root unless stated otherwise.

## Evaluate before switching

Run the flake checks:

```bash
nix flake check path:.
```

Check shell syntax after script changes:

```bash
python3 -m compileall -q setup
bash -n setup.sh scripts/*.sh scripts/lib/*.sh
```

Evaluate one host's system closure:

```bash
nix eval --raw \
  path:.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```

## Rebuild commands

Dry-activate first for higher-risk changes:

```bash
sudo nixos-rebuild dry-activate --flake path:.#<host>
```

Switch after review:

```bash
sudo nixos-rebuild switch --flake path:.#<host>
```

The setup wrapper can rebuild an existing target:

```bash
./setup.sh <host>
```

## Zsh aliases

Hosts importing `modules/programs/zsh.nix` receive aliases based on
`nixstead.host.repositoryPath` and `nixstead.host.configurationName`:

| Alias | Action |
| --- | --- |
| `rebuild` | Pure switch using tracked SOPS ciphertext |
| `dry-rebuild` | Pure dry activation |
| `rebuild-external` | Impure switch using `NIXSTEAD_SECRETS_DIR` |
| `rebuild-clean` | Compatibility alias for a pure switch |
| `update` | `nix flake update <repo>` |
| `ngc` | Delete old garbage-collectable Nix generations/store paths |

Use `rebuild-external` only when encrypted host files live outside the checkout.

## Health checks

### Preflight

```bash
nixstead --host <host> --secrets-dir "$PWD/secrets" check preflight
```

This checks required commands and files, evaluates the system closure, and
derives required secret domains from enabled registry entries, verifies SOPS
encryption, and confirms each required encrypted branch exists.

### Runtime homelab check

```bash
nixstead --host <host> --secrets-dir "$PWD/secrets" check runtime
```

This checks selected mounts, infrastructure reachability, systemd units,
listening ports, and HTTP endpoints.

The same registry-driven check runs automatically through
`nixstead-service-smoke-test.timer`, which defaults to a daily schedule and a
15-minute post-boot delay. It consumes immutable metadata and an executable from
the Nix store, so it also works for remote-flake consumers without a checkout.
Configure or disable it with:

```nix
nixstead.serviceSmokeTests = {
  enable = true;
  schedule = "daily";
};
```

Run it immediately with:

```bash
sudo systemctl start nixstead-service-smoke-test.service
journalctl --no-pager -u nixstead-service-smoke-test.service
```

Detailed checks for enabled development databases are included in the runtime
check. They verify database-specific settings and reject known default
credentials without duplicating the general unit and port checks.

### Secret-store regression check

```bash
nixstead --host <host> --secrets-dir "$PWD/secrets" check secrets store
```

This decrypts sensitive values only into a protected temporary directory and
checks the evaluated derivation/closure without printing matches. It catches a
service accidentally interpolating a runtime secret back into a derivation.

Warnings usually indicate optional reachability or HTTP behavior; failures
indicate missing requirements, inactive units, or non-listening endpoints.

## Inspecting state

Host options:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.host | jq
```

Service selections:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.services | jq
```

Enabled registry entries:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.serviceRegistry \
  | jq 'with_entries(select(.value.enabled))'
```

Systemd status and logs:

```bash
systemctl --no-pager status <unit>
journalctl -u <unit> -b --no-pager
```

Listening ports:

```bash
ss -lntup
```

## Updating inputs

```bash
nix flake update
nix flake check path:.
```

Review `flake.lock` and relevant package/service changes before switching. A
successful evaluation does not guarantee that upstream applications can migrate
existing data safely; check release notes for stateful services.

## Updating OCI containers

Use the registry-aware helper to see every managed component and its repository,
role, repository default, effective value, and host-managed override:

```bash
nixstead --host <host> images list
```

Set one component by tag. The helper obtains the immutable digest with `skopeo`,
stores the complete reference in `hosts/<host>/container-images.nix`, runs
`nix flake check path:.`, and restores the previous file if validation fails:

```bash
nixstead --host <host> images set --dry-run romm application 5.2.1
nixstead --host <host> images set romm application 5.2.1
```

The tool accepts a full `repository:tag` or `repository:tag@sha256:...` too. A
supplied digest is checked against the registry rather than trusted. It rejects
`latest`, repository substitutions, malformed references, and detected
downgrades unless `--allow-downgrade` is explicit.

Update related application and database images atomically by adding more
triplets. All tags are resolved before the generated file is changed:

```bash
nixstead --host <host> images set --dry-run \
  romm application 5.2.1 \
  romm database 11.4.5
```

Review the generated change or remove selected overrides:

```bash
nixstead --host <host> images diff
nixstead --host <host> images reset --dry-run romm application
nixstead --host <host> images reset romm application
```

Resetting returns the component to the repository default unless a higher
priority image value is declared directly in the host. A reset that the helper
can identify as a downgrade also requires `--allow-downgrade`. Database, cache,
and search-engine changes deserve particular care: back up state and review the
application's migration and rollback documentation first.

The generated file is an ordinary Nix attrset and may be reviewed or edited
directly. Every value must retain both a readable exact tag and an immutable
digest:

```nix
{
  "romm" = {
    "application" =
      "ghcr.io/rommapp/romm:5.2.1@sha256:<64 hexadecimal characters>";
  };
}
```

Hosts created by the setup wizard and the included host template conditionally
load this tracked file into `nixstead.containerImages.overrides`. Keeping the empty
file under version control ensures later changes are included by Git-backed
flake references as well as `path:.`. Generated values use a lower
module priority than direct declarations such as
`nixstead.services.media.romm.images.application`, so an intentional hand-written host
override still wins. The helper changes configuration only; it never rebuilds
or activates NixOS.

The tag documents the intended application version; [Docker runs the immutable
content selected by the digest](https://docs.docker.com/dhi/explore/security-concepts/digests/).
Database images use exact patch tags as well as a digest, so a configuration
review shows both application and database-version changes. The shared
container runtime also supplies [memory, CPU and PID
limits](https://docs.docker.com/engine/containers/resource_constraints/),
health checks, `no-new-privileges`, reduced capabilities, and read-only root
filesystems for containers whose writable state is fully mounted.

[`renovate.json`](../renovate.json) uses [Renovate's Docker digest
support](https://docs.renovatebot.com/docker/) to discover the annotated image
defaults in the service registry. Enable the Renovate app or run Renovate
against the repository to receive scheduled image PRs. Major Docker updates are
disabled, new releases wait three days, and automerge is disabled. Review
release notes and state migrations, run `nix flake check path:.`, and back up
stateful data before merging an image update. Merging only changes
configuration; activating the reviewed system remains a separate operator
action.

## Rollback

If a switch succeeds but runtime behavior is broken, select an older generation
from the bootloader or use NixOS generation commands appropriate to the system.
Do not delete old generations until the new system has been validated.

Configuration rollback does not automatically roll back application databases.
Back up state before migrations and use application-specific recovery guidance.

## Common problems

### “Cannot connect to the Nix daemon socket”

Run commands on the NixOS host with a functioning daemon and appropriate user
permissions. In restricted environments, the daemon socket may be unavailable
even though the Nix CLI exists.

### Flake input ignores a new file

Git-backed flakes only include tracked files. Add newly created Nix files to the
index before evaluating a `git+file`/GitHub-style source, or use `path:.` during
local development.

### Missing secret error

Confirm the enabled service's registry `secrets` list and create the matching
branch in `secrets/<host>.yaml`. Run `sops filestatus` and the host health check.
If using an external encrypted directory, pass it through
`NIXSTEAD_SECRETS_DIR` with `--impure`.

### Service is enabled but proxy/card is absent

Check that Nginx or Homepage is enabled, then inspect the resolved registry
entry. A service needs non-null `proxy` or `homepage` metadata to participate.

### Browser rejects local TLS

Install `~/.local/share/nixstead/<hostname>-nginx-ca.crt` on the client device
and verify that the requested domain matches the generated certificate. The
managed source is `/var/lib/nginx/local-ca/ca.crt`. Do not distribute the CA
private key.

Inspect renewal state and run an immediate renewal check with:

```bash
systemctl --no-pager status nginx-local-certificates.timer
sudo systemctl start nginx-local-certificates.service
journalctl --no-pager -u nginx-local-certificates.service
```

When using `nixstead.services.nginx.ca.certificateFile`, renew the external CA at its
source; the service only renews the leaf certificates it signs.

### Proxy returns connection errors

Verify the service's resolved port and IP, its systemd unit, and the listener:

```bash
systemctl --no-pager status <unit>
ss -lntp
```

Local registry proxies target loopback; external integrations target their
configured external IP.

### CIFS service paths are missing

Check network reachability, the runtime credentials file, and automount status:

```bash
systemctl --no-pager status remote-fs.target
mountpoint /mnt/media
```

Run the homelab health check as root when root-only credential paths need to be
verified.

### Setup generation failed

Read the reported hidden `.setup-recovery` path. The staged host is preserved
there when possible, while the public `hosts/<name>` path is freed for a clean
retry.

## Command summary

Run `nixstead --help` for the grouped public interface. Routine operations live
under `check`, `credentials`, `images`, and `backup`; DNS and Forgejo operations
use `dns` and `forge`. The optional `media` group contains transcoding, hardlink
inspection, RomM import, and Kavita library preparation. Use `help`, `-h`, or
`--help` after any group or operation to inspect the next level or its options.

Mutating operations require an explicit operation or flag such as `--apply`,
`--replace`, or `reset`. Start with dry-run behavior whenever available. Files
under `scripts/` are implementations shared by the CLI, setup, systemd, and
tests rather than additional public commands.
