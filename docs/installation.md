# Installation

Nixstead supports three installation models. The wizard can generate a separate
consumer flake, a clone or fork can contain its hosts, and advanced users can
compose the public flake API manually.

## Before you begin

You need:

- an installed, bootable NixOS system;
- network access to obtain the pinned Nix packages;
- a normal user with `sudo` access for activation; and
- a generated hardware configuration or access to
  `nixos-generate-config`.

The setup process does not partition disks or install NixOS from installation
media. Configure destructive storage layouts separately and verify all device
paths before enabling the NAS stack.

## Model A: generate a standalone flake

This is the recommended path for a new homelab host. It keeps machine settings
and secrets in your directory while pinning Nixstead as an upstream dependency.

```bash
nix run github:Kalmera74/nixstead#setup -- \
  --output ~/my-homelab \
  --generate-only
```

Do not invoke the wizard with `sudo`. It detects whether elevation is necessary
and requests it at the appropriate points.

The wizard will:

1. preserve the installed system's `system.stateVersion`;
2. select or generate a hardware configuration;
3. collect the host name, user, network, locale, and hardware settings;
4. apply a service preset and let you customize every service category;
5. choose whether Nginx is reachable locally, over a restricted LAN, through
   Tailscale, or without firewall restrictions;
6. collect details required by selected storage and infrastructure features;
7. select program groups and user privileges;
8. write a consumer `flake.nix`, lock file, host configuration, hardware
   configuration, image overrides, and secrets directory;
9. enroll admin and host SOPS recipients, generate bootstrap credentials, and
   create non-interactive placeholders for application-issued credentials;
10. evaluate the new flake target and run the pre-switch health check; and
11. optionally run `nixos-rebuild switch`.

Supported ARR, Seerr and qBittorrent credentials are enrolled in SOPS and delivered
automatically during activation when shared credentials are enabled. The host
needs its enrolled SOPS identity and access to the writable encrypted source.
Existing credentials are reused. No manual sync or second rebuild is needed.
After initial setup, populate credentials for other dashboard widgets:

```bash
nixstead --host <host> credentials configure homepage
```

This command prompts for enabled unmanaged widgets; rebuild to deploy those
values. qBittorrent's password is stored once in SOPS, with its native hash
derived during startup. To rotate it explicitly:

```bash
nixstead --host <host> credentials rotate qbittorrent
```

Automatic credential refresh delivers the new password to qBittorrent and its
consumers within about a minute. See [credential operations](media-operations.md#canonical-sops-credentials)
for custom source paths and the manual-delivery opt-out.

The output directory must not already exist. Use `--nixstead-url` to generate
against a fork, branch, or local source instead of the default GitHub input.
After reviewing the output, activate it with:

```bash
sudo nixos-rebuild switch --flake path:~/my-homelab#<host>
```

## Model B: clone or fork and run repo-locally

Choose this model when you intend to modify Nixstead itself, test unreleased
changes, or keep framework and machine configuration in one repository.

```bash
git clone https://github.com/Kalmera74/nixstead.git
cd nixstead
./setup.sh --repo-local --generate-only
```

This writes `hosts/<host>/` and preserves the existing clone-oriented workflow.
You can supply a hardware file explicitly:

```bash
./setup.sh --repo-local --new-host \
  --hardware-config /etc/nixos/hardware-configuration.nix \
  --generate-only
```

If Zsh was selected, start a new login shell after activation to use the
generated `rebuild` and `dry-rebuild` aliases.

## Model C: initialize the public host template

This model keeps only your local machine configuration in your repository. Nix
fetches Nixstead from GitHub and pins its revision in `flake.lock`.

```bash
mkdir -p ~/my-nixos
cd ~/my-nixos
nix flake init -t github:Kalmera74/nixstead#host
```

Generate or copy the real hardware configuration:

```bash
sudo nixos-generate-config --show-hardware-config \
  > hardware-configuration.nix
```

Then add the import to `configuration.nix`:

```nix
{
  imports = [./hardware-configuration.nix];
}
```

Replace the placeholder host name, IP address, user, and state version before
building:

```bash
nix flake check
sudo nixos-rebuild switch --flake path:.#my-host
```

If enabled services need credentials, import the SOPS-enabled public module,
set `nixstead.secrets.sopsFile` to an encrypted file owned by the consumer flake, and
follow [Secrets](secrets.md).

## Model C: use a repository-local host

The root flake exposes every valid `hosts/<name>/` directory automatically. A
host created in your clone or fork can be activated directly:

```bash
sudo nixos-rebuild switch --flake path:.#<host-name>
```

Do not reuse another machine's host directory. It contains bootloader,
hardware, network, disk, and storage assumptions. Create a new host through the
wizard or template instead.

## First activation checklist

Before switching, verify:

- `system.stateVersion` matches the original installed system;
- `nixpkgs.hostPlatform` is declared by the hardware configuration;
- the bootloader device is correct;
- every `/dev/disk/by-*` and network-share path exists or is intentionally
  optional;
- the configured LAN and infrastructure addresses are correct;
- the host has its SSH private key and every required encrypted secret branch;
- you have a working local login or recovery path if networking changes.

Run:

```bash
nixstead --host <host> --secrets-dir "$PWD/secrets" check preflight
nix flake check path:.
```

The health check derives requirements from the selected host, so disabled
services do not require their units, mounts, or secret domains.

Empty Homepage integration placeholders are expected during first activation.
Run the post-install command after the applications have issued their API keys.

## Updating

In a cloned repository:

```bash
nix flake update
nix flake check path:.
sudo nixos-rebuild switch --flake path:.#<host>
```

In a consumer flake, the same `nix flake update` command updates the pinned
Nixstead and Nixpkgs revisions. Review lock-file changes before activation.
