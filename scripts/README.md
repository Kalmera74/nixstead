# Command-line tools

Nixstead exposes one public command with grouped subcommands:

```text
nixstead setup ...
nixstead check ...
nixstead credentials ...
nixstead images ...
nixstead backup ...
nixstead dns ...
nixstead forge ...
nixstead media ...
```

Enable administration commands on NixOS with:

```nix
nixstead.tools.enable = true;
```

Media-library subcommands carry additional dependencies and are independently
optional:

```nix
nixstead.tools.media.enable = true;
```

The command can also be run without installing the module:

```bash
nix run path:.#nixstead -- --host <host> check preflight
nix run path:.#nixstead -- --host <host> images list
```

Installed commands inherit `nixstead.host.repositoryPath` and
`nixstead.host.configurationName`. Generic flake invocations require the current
directory to be the checkout or an explicit `--repo-root`, and require `--host`
when an operation evaluates a host configuration. `--secrets-dir` selects an
external encrypted secrets directory. The deprecated `NIXCONFIG_SECRETS_DIR`
environment alias remains supported.

## Command groups

| Command | Purpose |
| --- | --- |
| `nixstead setup wizard` | Create, validate, or switch a host through the setup application |
| `nixstead setup sops` | Enroll admin and host SOPS recipients for the selected host |
| `nixstead check preflight` | Validate evaluation and required encrypted secret branches before a rebuild |
| `nixstead check runtime` | Check mounts, units, endpoints, and enabled database-service details |
| `nixstead check secrets homepage` | Compare Homepage keys with the tracked schema |
| `nixstead check secrets store` | Scan the evaluated store closure for decrypted secret values |
| `nixstead credentials bootstrap` | Generate one credential target or all branches required by enabled services |
| `nixstead credentials configure homepage` | Prompt for post-install Homepage integrations |
| `nixstead credentials list/show/sync/rotate` | Inspect and maintain canonical or deployed credentials |
| `nixstead images list/set/reset/diff` | Manage digest-pinned OCI image overrides |
| `nixstead backup create/verify/restore` | Create, validate, or restore registry-driven service-state backups |
| `nixstead dns sync` | Manually preview or apply Pi-hole DNS reconciliation |
| `nixstead forge mirror` | Import GitHub repositories as Forgejo mirrors using a token file |
| `nixstead media transcode` | Validated AV1/HEVC conversion with optional replacement |
| `nixstead media hardlinks` | Compare hardlink trees or find shared files |
| `nixstead media rom-import` | Map and copy a Batocera library into RomM |
| `nixstead media kavita-import` | Organize loose books into Kavita-compatible folders |

Use `help`, `-h`, or `--help` at the root, group, or operation level. Mutating
commands require an explicit operation or flag such as `--apply`, `--reset`, or
`--replace`. Review dry-run output and paths before applying a change.

## Internal implementations

The remaining scripts in this directory are implementation details used by the
public command, setup application, systemd services, and tests. Do not add a new
top-level executable for a workflow that fits an existing command group.

Configuration-aware implementations use `lib/nixstead.sh` and resolve service
metadata from `nixstead.serviceRegistry`. System services pass immutable registry
metadata directly, allowing backup, DNS, and runtime-health jobs to operate
without a mutable checkout.

## Credential behavior

Credential generation constructs JSON directly and passes it to SOPS; plaintext
credentials never enter Nix evaluation. Manual Nextcloud, Paperless, and Kavita
preseed targets use effective configured file paths. Paperless preseeding refuses
to replace the native active environment file.

Managed media credentials use one SOPS entry per service. `credentials sync`
enrolls missing keys, and `credentials show --runtime` selects deployed values.
Automatic enrollment saves missing keys before delivery and refreshes affected
consumers. Manual mode requires a rebuild after saved changes.

See [Operations](../docs/operations.md), [Secrets](../docs/secrets.md), and
[Storage and backups](../docs/storage-backups.md).
