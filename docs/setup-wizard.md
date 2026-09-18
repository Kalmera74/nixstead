# Setup wizard

The setup application creates either a standalone consumer flake or a host
inside a Nixstead clone, and can switch the running NixOS system to it. Its
service questions come from the central registry,
so preset membership, labels, ordering, secret requirements, and option paths do
not need a second hardcoded service list.

## Commands

```bash
# Recommended: create a separate consumer flake
nix run github:Kalmera74/nixstead#setup -- --output ~/my-homelab

# Create hosts/<name> inside a clone or fork
./setup.sh --repo-local

# Create and validate either mode without switching
nix run github:Kalmera74/nixstead#setup -- --output ~/my-homelab --generate-only
./setup.sh --repo-local --generate-only

# Use a particular hardware configuration
./setup.sh --repo-local --new-host --hardware-config /path/to/hardware-configuration.nix

# Rebuild an existing discovered host
./setup.sh <host-name>
```

Use `./setup.sh --help` for the current command-line reference.

Standalone output is a new directory containing `flake.nix`, `flake.lock`,
`configuration.nix`, `hardware-configuration.nix`, `container-images.nix`, and
`secrets/`. Its flake imports only supported `nixstead.nixosModules` exports.
Use `--nixstead-url <flake-reference>` to target a fork or local checkout.

## Interface behavior

The `setup.sh` file is the clone-oriented compatibility launcher. It enters a
temporary Nix shell containing the `.#setup` Python application, selects the
repo-local context, and exits the shell when setup finishes. The public
`apps.setup` entrypoint packages the same application for standalone use. Python
therefore does not need to be installed globally in either mode.
The application is included as readable source under `setup/`, so no opaque
binary is required or committed. The interactive controls use the
[Textual](https://textual.textualize.io/) terminal UI toolkit. They support
typed prompts, arrow-key menus, Space to toggle checklists, and Enter to
confirm. The application realizes the flake's `setup-runtime` package
for SOPS, age, and `ssh-to-age` when needed; secret management tools remain
required for secret-backed services.
When setup is run without a usable TTY (for example in a test harness), it uses
plain line prompts instead.

The wizard keeps configuration in typed Python state while it collects the
answers. No host is written until the configuration has been collected.

## Service selection

The wizard starts from one of these choices:

- Minimal
- Media server
- Development server
- Full (advanced/demo)
- Custom

It then presents service checklists by registry group. Selecting a preset sets
the initial checkboxes and shows the exact services that will be enabled. The
wizard then asks whether to modify the preset; choosing No advances directly to
the next section, while choosing Yes opens the service and program checklists.
Machine-specific integrations are asked separately because their addresses,
disks, or shares cannot be inferred from a generic preset. Completed sections
have Previous and Next controls so choices can be revisited before review.

Related text fields are presented together on one form page. Tab and
Shift+Tab move between fields, and validation returns to the same form with the
entered values preserved.

The generated host records the selection as `nixstead.preset`. It writes explicit
service options only when the final answer differs from the chosen preset. A
custom selection becomes:

```nix
nixstead.preset = "none";
```

followed by explicit enabled-service choices.

The full preset deliberately carries an advanced/demo label: it enables the
entire registry-controlled catalog (currently dozens of services) and is not a
recommended first-host default. Start with media-starter, minimal, development,
or custom and add services deliberately.

## Service access policy

When Nginx is selected, the wizard requires one access mode before generation:

- local machine only, which explicitly keeps Nginx on loopback;
- LAN, restricted by at least one interface name or trusted IPv4 source CIDR;
- Tailscale, which enables Tailscale when necessary and selects `tailscale0`;
- public/unrestricted, which requires a second warning confirmation.

The generated host writes the choice to
`nixstead.host.network.exposure.services.nginx`. The final review displays the chosen
mode. Public exposure only changes the NixOS firewall; the operator remains
responsible for router forwarding, public DNS, authentication, and appropriate
TLS certificates.

## First-boot credentials

Before activation, setup enrolls admin and host SOPS identities and prepares the
encrypted document. At activation, shared media credential enrollment reuses SOPS
keys, imports existing native keys, or generates missing keys before applications
start. Values are saved encrypted and verified before delivery to applications,
Homepage and other consumers. There is no manual sync or second rebuild for
these managed credentials. Setup does not ask for application-issued API keys.

After activation and initial application setup, run:

```bash
nixstead --host <host> credentials configure homepage
```

This handles enabled unmanaged widgets; rebuild to deploy their values.
qBittorrent's password is stored once; its native hash is derived at startup.
See [credential operations](media-operations.md#canonical-sops-credentials) for
writable source configuration, failures, rotation, inspection and manual opt-out.

### NAS storage setup

If Local NAS is selected, the wizard opens a dedicated storage section before
writing the host. It discovers whole non-swap disks with `lsblk` and presents
their stable path, kernel path, model, UUID, size, filesystem, partitions, and
available space. The user first selects all disks for the NAS, then chooses
whether one or more of those disks should be SnapRAID parity disks; every
remaining selected disk becomes mergerfs data. The wizard then collects mount
points, filesystem types, and mount options for the selected devices. It does
not format, partition, or otherwise modify disks. If no eligible disk is
available, the wizard offers to disable NAS and continue with the remaining
setup instead of aborting the wizard.

## Generated files

For a host named `homelab`, the wizard creates:

```text
hosts/homelab/
├── default.nix
└── hardware-configuration.nix
```

`default.nix` contains:

- selected program-module imports;
- the preserved `system.stateVersion`;
- `nixstead.preset`;
- the deliberate Nginx exposure policy and any LAN selectors;
- `nixstead.host.hostName` and `nixstead.host.configurationName`;
- the clone path as `nixstead.host.repositoryPath`;
- network, locale, user, and optional hardware settings;
- the SSH listener port, optional public key, and authentication policy;
- service choices that differ from the preset;
- host-specific integration/storage settings, including explicit service path
  overrides for enabled services placed on selected CIFS roots; and
- the chosen bootloader configuration.

Setting `configurationName` is important: the optional Zsh module uses it to
build host-correct rebuild aliases.

The wizard offers three SSH-key choices for the primary user:

- paste an existing public key;
- generate a new Ed25519 keypair; or
- use password authentication without an SSH key.

Pasted keys are validated and private-key input is rejected. Generated keys are
created only after the final review as
`~/.local/share/nixstead/<host>-ssh-ed25519` and its `.pub` companion.
`ssh-keygen` offers its normal passphrase prompt, the wizard reports both output
paths, and only the public key is written to the host configuration.
When no terminal is attached, generation is non-interactive and the wizard
clearly reports that the private key has no passphrase.

The same directory holds `sops-age-key.txt` and the public Nginx CA certificate
when those features are selected. The generated host records the relative path
as `nixstead.host.user.generatedFilesDirectory` and exports `SOPS_AGE_KEY_FILE` for
login sessions. The wizard also passes that identity to its credential and
preflight commands immediately, without requiring activation or a new login.
When no key is selected, password authentication is enabled automatically. Root
SSH login defaults off in every mode.

Direct Docker access is never selected automatically. The privilege checklist
labels it as root-equivalent because [Docker daemon access grants root-level
control of the host](https://docs.docker.com/engine/install/linux-postinstall/);
running the selected container services does not require that access.

## Hardware source order

The wizard uses the first available source:

1. the path passed to `--hardware-config`;
2. `/etc/nixos/hardware-configuration.nix`; or
3. output from `nixos-generate-config --show-hardware-config`.

It validates that the result declares a supported `nixpkgs.hostPlatform`.

## Secrets

After service selection, the wizard can invoke the credential helper for
required secret domains. The central registry decides which domains are needed.
It creates an admin age identity when needed, enrolls the host's SSH Ed25519
recipient in `.sops.yaml`, and writes encrypted branches to
`secrets/<host>.yaml`. The generated host enables `nixstead.secrets` only when one of
its selected services requires credentials.

See [Secrets](secrets.md) for formats and manual generation.

## Validation and switching

Before switching, the wizard runs the host-aware health check unless
`--skip-healthcheck` was supplied. It evaluates the resulting configuration,
checks enabled-service requirements, verifies SOPS encryption and required
branches, and reports missing secret or runtime paths.

The final switch is equivalent to:

```bash
sudo nixos-rebuild switch \
  --option experimental-features 'nix-command flakes' \
  --flake path:<repo>#<host>
```

`--generate-only` performs generation and validation but skips this command.

## Recovery behavior

New hosts are assembled in a temporary staging directory. If validation is
declined or fails, the generated repo-local host or standalone flake is moved to
a hidden sibling `.setup-recovery` path. This leaves the requested destination
free for another attempt and avoids a partial automatic host-discovery entry.

Read the final error output for the exact `.setup-recovery` path. Inspect or
copy useful files from it, correct the underlying issue, and rerun the wizard.

## Editing after generation

The wizard is an initializer, not a permanent restriction. You can edit the
generated host normally:

```nix
{
  nixstead.services.arr.radarr.port = 7879;
  nixstead.services.media.kiwix.enable = false;
}
```

Run the health check and `nix flake check path:.` after manual changes.

## State version preflight and foundation effects

Before opening the interview, setup detects the original `system.stateVersion`.
If `/etc/nixos/configuration.nix` is missing, imports the value, or has an
ambiguous assignment, provide it explicitly:

```bash
./setup.sh --generate-only --state-version 24.11 --hardware-config /srv/nixos/hardware-configuration.nix
# A different file with a literal assignment can also be inspected:
./setup.sh --generate-only --configuration /srv/nixos/host.nix
```

Use your installed host's original value, not today's NixOS release. These
options apply only to new host generation. The detector is a convenience and
does not evaluate arbitrary imported modules.

`media-starter` is the recommended initial role. The selection page shows runtime
coverage and storage/resource notes; expand the catalog through the service
checklists. NAS Samba enablement alone exports no directories: explicitly
configure [authenticated shares](services/samba.md).

The generated complete host enables NetworkManager and SSH, opens the SSH port,
applies your locale/timezone, and manages the selected user, groups and Zsh
shell. Existing servers that only need services can use the
[service module exports](module-api.md) instead. See the
[independent installation trial](installation-trial.md) for the full validation
journey, including update and empty-state restore.
