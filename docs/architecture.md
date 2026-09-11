# Architecture

Nixstead separates reusable behavior from machine-specific choices. The flake
composes a complete module framework with one discovered host directory; the
host then selects a preset and overrides concrete services.

## Evaluation flow

```text
flake.nix
  │
  ├─ discovers hosts/<configuration>/default.nix
  │
  └─ nixosSystem
       ├─ nixosModules.default
       │    ├─ upstream sops-nix module
       │    ├─ modules/secrets/sops.nix
       │    ├─ modules/base.nix
       │    │    ├─ modules/core/options.nix
       │    │    ├─ modules/hardware/hardware.nix
       │    │    └─ modules/system/system.nix
       │    └─ modules/services/services.nix
       │         ├─ stack/service implementations
       │         ├─ registry integrations
       │         └─ preset renderer
       ├─ hosts/<configuration>/default.nix
       └─ nixstead.host.configurationName = <configuration>
```

The selected hardware configuration supplies `nixpkgs.hostPlatform`, so the
root flake does not hardcode one architecture for all hosts.

## Flake outputs

The root flake exposes:

- `nixosConfigurations.<host>` for every valid directory under `hosts/`;
- `nixosModules.default`, `base`, `services`, individual stack modules, and
  optional `program-*` groups;
- four compatibility `nixosModules.profile-*` wrappers;
- `templates.host` for external consumers;
- `lib.serviceRegistry` for tools that need static metadata;
- `packages.<system>.setup` and `apps.<system>.setup` for the packaged Python
  wizard and standalone consumer-flake generator;
- `packages.<system>.setup-runtime` for the pinned SOPS/age helper runtime;
- `packages.<system>.nixstead-{admin,media,}-tools` plus individual command
  packages and matching `apps.<system>` entries; and
- `checks.<system>.public-module-api` for API and preset parity checks.

See [Public module API](module-api.md) for the supported external boundary.

## Module layers

### Core options

`modules/core/options.nix` owns the typed `nixstead.host` interface and the helpers
used to define consistent service options. It imports the static registry,
combines each registry entry with evaluated `nixstead.services` state, and exposes the
result as read-only `nixstead.serviceRegistry`.

Static registry data answers “what does this service integrate with?” Resolved
registry data also answers “is it enabled on this host, and what are its current
settings?”

### Base module

`modules/base.nix` imports core options, optional hardware modules, and shared
system behavior. It deliberately excludes application services. Public
consumers can use it when they want the host foundation without the homelab
catalog.

### Default module

`modules/default.nix` imports `base.nix` plus the complete service orchestrator.
This is the normal entry point for repository hosts and new public consumers.

### Service modules

`modules/services/services.nix` imports every available implementation. An
import defines the option; it does not automatically enable all applications.
Stack wrappers define parent and child options, while child files contain
implementation-specific NixOS configuration.

### Preset renderer

`modules/services/presets.nix` defines `nixstead.preset` and uses registry membership
to apply `lib.mkDefault true` at selected service paths. Host assignments have
higher priority and can disable any preset member.

### Registry integration renderers

Repeated cross-service behavior is generated from `nixstead.serviceRegistry`:

- `registry-integrations.nix` renders exposure-aware firewall policy;
- `nginx/registry-proxies.nix` renders virtual hosts;
- `homepage/services-registry.nix` renders dashboard cards;
- health and DNS scripts query resolved registry entries; and
- backup, restore, setup, and credential scripts query matching metadata.

## Ownership boundaries

Use the following rule when deciding where a change belongs:

| Concern | Owner |
| --- | --- |
| Machine identity, addresses, user, locale | `nixstead.host` in a host file |
| Hardware facts and bootloader | Host hardware/default files |
| Shared machine behavior | `modules/system/` or `modules/hardware/` |
| Optional command-line packages | `modules/programs/` |
| Service identity and repeated integrations | Stack fragments in `modules/services/registry/`, aggregated by `registry.nix` |
| Service package, user, container, directories, lifecycle | Concrete service module |
| Service selection starting point | Registry preset metadata |
| Encrypted credentials and runtime ownership | sops-nix module plus encrypted host file |

This keeps the registry useful without turning it into a place for arbitrary
implementation code.

## Host discovery

A directory becomes a flake host when it matches:

```text
hosts/<name>/default.nix
```

`flake.nix` ignores non-directory entries and any reserved internal directory.
The directory name becomes `nixosConfigurations.<name>` and is also assigned to
`nixstead.host.configurationName`.

Adding another valid host therefore requires no root-flake edit.

## Option priority

The architecture relies on Nix module priorities:

1. ordinary option defaults establish disabled/safe behavior;
2. parent stack toggles and presets use default-priority values; and
3. explicit host assignments override those defaults.

For example:

```nix
{
  nixstead.preset = "media-server";
  nixstead.services.arr.lidarr.enable = false;
}
```

The preset selects Lidarr, but the host assignment wins.

## Public versus internal interfaces

The stable reuse boundary is the set of names exported under `nixosModules`,
`templates`, and `lib`. Paths under `modules/` are organized for this repository
and may evolve. Repository hosts can use internal program modules directly
because they are versioned together with the flake.
