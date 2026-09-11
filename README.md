# Nixstead

Nixstead is a modular NixOS homelab platform for media, development, local AI,
productivity, storage, and self-hosted services. It provides a guided setup
wizard, reusable NixOS modules, service presets, encrypted secrets, and a
registry-driven operations toolkit.

## Quick start

You need an installed, bootable NixOS system, network access, and a normal user
with `sudo` access. Nixstead configures an existing system; it does not
partition disks, create filesystems, or install NixOS. Read the
[installation guide](docs/installation.md) before using it with existing
storage or service data.

### Generate a standalone homelab flake

This is the recommended approach. Your machine configuration stays in its own
directory while `flake.lock` pins Nixstead as an upstream dependency.

```bash
nix run github:Kalmera74/nixstead#setup -- \
  --output ~/my-homelab \
  --generate-only
```

The output directory must not already exist. The wizard creates the flake,
hardware configuration, host configuration, container-image overrides, and
secrets directory, then validates the result without changing the running
system.

After reviewing the generated files, activate the selected host:

```bash
sudo nixos-rebuild switch --flake path:~/my-homelab#<host-name>
```

Omit `--generate-only` on the initial run if you want the wizard to offer
activation. See the [setup wizard reference](docs/setup-wizard.md) for custom
Nixstead inputs, hardware configuration, secrets, and recovery behavior.

### Use a clone or fork

Choose this workflow when you want to modify Nixstead itself or keep your host
configuration in the same repository.

```bash
git clone https://github.com/Kalmera74/nixstead.git
cd nixstead
./setup.sh --repo-local --generate-only
```

The wizard creates `hosts/<name>/` and a matching flake target. Run
`./setup.sh <host-name>` when you are ready to rebuild an existing generated
host.

### Start from the public module template

Experienced NixOS users can create and maintain a consumer flake directly:

```bash
mkdir my-nixos && cd my-nixos
nix flake init -t github:Kalmera74/nixstead#host
```

See the [public module API](docs/module-api.md) for supported exports and
complete examples.

## Features

- Registry-driven presets with independently overrideable service toggles.
- A broad [service catalog](docs/services.md) spanning ARR, media,
  observability, datastores, local AI, productivity, home automation, storage,
  and external infrastructure.
- Nginx reverse proxies, local TLS, exposure-aware firewall rules, Homepage
  cards, health checks, and DNS metadata generated from the same registry.
- SOPS-encrypted per-host credentials delivered to services at runtime without
  placing plaintext secrets in the Nix store.
- Optional Tailscale, WireGuard application isolation, CIFS clients, and
  mergerfs/SnapRAID/Samba NAS support.
- Encrypted Borg service backups with retention and guarded restore workflows.
- Digest-pinned OCI image updates and downgrades with reviewable per-host
  overrides and downgrade protection.
- A unified `nixstead` command for health checks, credentials, images, backups,
  DNS, forge imports, and media operations.
- A stable public module API, reusable host template, and support for both
  standalone consumer flakes and repository-local hosts.

### Presets at a glance

| Preset | Intended starting point |
| --- | --- |
| `none` | No automatic service selection |
| `minimal` | Remote administration with Tailscale |
| `media-starter` | Core streaming, automation, proxy, and dashboard services |
| `media-server` | Extended ARR and media catalog |
| `development` | Monitoring, datastores, developer tools, and ingress |
| `full` | Broad application-host selection |

Presets provide defaults rather than policy: every child service can still be
enabled or disabled individually. Machine-specific storage and infrastructure
integrations are never enabled merely by selecting a preset. See
[presets and overrides](docs/presets.md) for exact membership and examples.

## Documentation

- [Documentation index](docs/README.md) — all user and maintainer guides
- [Installation](docs/installation.md) — prerequisites and setup models
- [Setup wizard](docs/setup-wizard.md) — options, generated files, and recovery
- [Configuration](docs/configuration.md) — host settings and service overrides
- [Services](docs/services.md) and [per-service guides](docs/services/README.md)
- [Networking](docs/networking.md) — Nginx, TLS, firewall, DNS, and Homepage
- [Secrets](docs/secrets.md) — SOPS enrollment and credential management
- [Storage and backups](docs/storage-backups.md) — storage layouts and recovery
- [Operations](docs/operations.md) and [command reference](scripts/README.md)
- [Support matrix](docs/support-matrix.md) and
  [compatibility notes](docs/compatibility.md)
- [Architecture](docs/architecture.md), [public module API](docs/module-api.md),
  and [development guide](docs/development.md)
