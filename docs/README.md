# Documentation

This directory contains the detailed user and maintainer guides for Nixstead.
Start with the installation path that matches how you want to use the project.

## Getting started

- [Installation](installation.md) — prerequisites, cloned-repository setup,
  public-template use, and first activation.
- [Setup wizard](setup-wizard.md) — wizard flow, generated files, recovery, and
  non-interactive considerations.
- [Configuring a host](configuration.md) — `nixstead.host`, program imports, service
  options, overrides, and worked examples.
- [Presets](presets.md) — exact preset behavior and why presets remain
  overrideable.

## Features and operations

- [Services](services.md) — service catalog, option shapes, stacks, and examples.
- [Per-service guides](services/README.md) — implementation, configuration,
  storage, first-login credentials, and operations for every catalog entry.
- [Networking](networking.md) — firewall exposure, Nginx, local TLS, Homepage,
  Pi-hole DNS, and Tailscale.
- [Secrets](secrets.md) — sops-nix, host enrollment, encrypted schemas,
  credential generation, validation, migration, and threat model.
- [Storage and backups](storage-backups.md) — CIFS, local NAS, service paths,
  encrypted Borg backups, retention, and guarded restores.
- [Operations](operations.md) — rebuilds, updates, health checks, inspection,
  failure recovery, and troubleshooting.
- [Compatibility](compatibility.md) — tested inputs, architectures, migrations,
  and recovery coverage.
- [Installation and update validation](installation-trial.md) — manual checks
  on fresh VMs with an independent client.

## Architecture and reuse

- [Architecture](architecture.md) — flake outputs, host discovery, module layers,
  evaluation flow, and ownership boundaries.
- [Central service registry](service-registry.md) — metadata schema, consumers,
  resolved state, and adding a service.
- [Public module API](module-api.md) — supported `nixosModules`, the host
  template, and external consumer examples.
- [Development](development.md) — repository conventions, adding hosts and
  services, tests, and documentation expectations.

Every major source directory also includes a short local README. Those files
answer “what belongs here?” while these guides explain cross-cutting workflows.
