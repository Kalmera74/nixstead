# Public module API

The flake exposes a curated NixOS module API for external consumers. Use these
exports instead of repository-internal paths. Nix fetches and pins the GitHub
repository automatically through the consumer's `flake.lock`.

## Core exports

| Export | Purpose |
| --- | --- |
| `nixosModules.default` | Complete framework: typed host options, hardware/system modules, presets, and all service implementations |
| `nixosModules.base` | Typed host options plus shared hardware and system behavior, without application services |
| `nixosModules.services` | Shared option dependencies plus every service implementation |
| `nixosModules.secrets` | Typed host options plus the sops-nix integration |
| `nixosModules.tools` | Typed host options plus opt-in packaged administration and media commands |

`default` is the normal starting point.

The optional program groups are exported as `nixosModules.program-core`,
`program-development`, `program-hardware`, `program-networking`, `program-media`,
`program-backup`, `program-zsh`, and `program-yazi`. Import them alongside
`nixosModules.default`; the standalone wizard does this automatically.

CI tests the exact `nixos-unstable` revision in `flake.lock`. Stable Nixpkgs
input overrides are **unverified** and may lack options/packages required by the
modules; they are not a supported production baseline. Keep a consumer's
`inputs.nixstead.inputs.nixpkgs.follows` aligned with its selected input and run
all relevant checks for any override. See [compatibility notes](compatibility.md).

`default` and `base` enable NetworkManager, SSH and its firewall port, apply the
configured locale/timezone (defaults: `en_US.UTF-8`, UTC, US console keymap), and
set the host name. When `nixstead.host.user.enable = true`, they manage that
user's identity, groups and Zsh shell; the wizard selects this explicitly.
For an existing server, import `nixosModules.services` or individual service
exports to retain your existing machine/user/network foundation.

## Stack exports

These modules can be composed independently:

- `nixosModules.arr`
- `nixosModules.media`
- `nixosModules.dev`
- `nixosModules.localai`
- `nixosModules.productivity`
- `nixosModules.cifs`
- `nixosModules.nas`
- `nixosModules.external`
- `nixosModules.nginx`
- `nixosModules.homepage`

Standalone service exports are also available for services that do not form a
coherent multi-service stack:

- `nixosModules.vaultwarden`
- `nixosModules.homeassistant`
- `nixosModules.authentik`
- `nixosModules.tailscale`
- `nixosModules.wireguard`
- `nixosModules.syncthing`
- `nixosModules.scrutiny`

The exports include their shared option and registry-integration dependencies.
They define options but do not generally enable the stack. `external` defines
the Pi-hole, Proxmox, and TrueNAS integration options.

Stack composition is intended for advanced consumers who want a smaller option
surface. Most users should import `default` and enable only desired services.

## Consumer flake example

```nix
{
  description = "My NixOS homelab";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixstead = {
      url = "github:Kalmera74/nixstead";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixstead,
    ...
  }: {
    nixosConfigurations.media = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixstead.nixosModules.default
        ./hardware-configuration.nix
        {
          # Use 26.05 for a new 26.05 install; retain the original value when
          # migrating an existing machine.
          system.stateVersion = "26.05";
          nixstead.preset = "media-starter";
          nixstead.tools.enable = true;

          nixstead.host = {
            hostName = "media";
            configurationName = "media";
            repositoryPath = "/etc/nixos";
            network.lan = "192.168.1.20";
            user = {
              enable = true;
              name = "admin";
              description = "Administrator";
            };
          };

          nixstead.services.arr.lidarr.enable = false;
        }
      ];
    };
  };
}
```

Build it with:

```bash
sudo nixos-rebuild switch --flake path:.#media
```

## Packaged commands

`nixosModules.default` and `nixosModules.base` define the command options. The
standalone `nixosModules.tools` export is available for configurations that do
not import either foundation module.

```nix
nixstead.tools = {
  enable = true;
  media.enable = true;
};
```

`nixstead.tools.enable` installs the grouped `nixstead` administration command.
The separate media toggle adds FFmpeg and the optional media/library subcommands.
The command is available on the normal system `PATH` after rebuilding.

The wrappers default to `nixstead.host.repositoryPath` and
`nixstead.host.configurationName`, while still allowing
`NIXSTEAD_REPOSITORY_ROOT` and `NIXSTEAD_HOST` overrides. Flake consumers can
also run a command without installing it:

```bash
nix run github:Kalmera74/nixstead#nixstead -- --host <host> check preflight
```

The setup application is also a public app and can create a pinned consumer
flake without cloning Nixstead:

```bash
nix run github:Kalmera74/nixstead#setup -- --output ~/my-homelab
```

## Host template

Initialize the included starter:

```bash
nix flake init -t github:Kalmera74/nixstead#host
```

The template contains a consumer `flake.nix`, a placeholder
`configuration.nix`, and a short README. Add a real hardware configuration and
replace all placeholder host settings before activation. Its Nixstead input
follows the consumer's Nixpkgs input so both evaluate against the same revision.

## Presets

The complete module defines:

```nix
nixstead.preset = "none";
```

Allowed values are `none`, `minimal`, `media-server`, `development`, and `full`.
See [Presets](presets.md) for exact membership and override behavior.

The API retains four compatibility wrappers:

- `nixosModules.profile-minimal`
- `nixosModules.profile-media-server`
- `nixosModules.profile-development`
- `nixosModules.profile-full`

Each imports the complete module and selects the corresponding preset. New
configurations should import `nixosModules.default` and set `nixstead.preset`.

## Static service registry

Tools can consume the un-evaluated registry:

```nix
nixstead.lib.serviceRegistry
```

An evaluated system exposes host-resolved state at:

```nix
config.nixstead.serviceRegistry
```

Use the resolved form when the answer depends on host overrides or enabled
state.

## Version pinning

By default, a consumer's `flake.lock` pins an exact Nixstead revision. Update
intentionally:

```bash
nix flake lock --update-input nixstead
nix flake check
```

You may pin a branch, tag, or revision in the input URL according to normal Nix
flake syntax. Review changes before updating stateful services.

## Secrets in consumer flakes

Every public service export includes sops-nix. A consumer that enables a
secret-backed service owns its encrypted file and points the module at it:

```nix
nixstead.secrets = {
  enable = true;
  sopsFile = ./secrets/media.yaml;
};
```

Pure rebuilds then work normally:

```bash
sudo nixos-rebuild switch --flake path:.#media
```

The encrypted YAML may be committed; private age/SSH identities and decrypted
exports must not be. `NIXSTEAD_SECRETS_DIR` remains available as an impure
encrypted-directory override. See [Secrets](secrets.md).

## Compatibility boundary

The supported reuse boundary consists of names under:

- `nixosModules`
- `packages` and `apps`
- `templates`
- `lib`
- the typed `nixstead.host`, `nixstead.system`, `nixstead.tools`, `nixstead.backups`, `nixstead.containerImages`,
  `nixstead.preset`, and `nixstead.services` options

Internal paths may change as the repository evolves. Public API checks force
`system.build.toplevel` for every exported module with a representative
configuration and for the host template. They also validate stack behavior,
compare preset membership with the registry, and exercise overrides.

Scheduled backups, restore rehearsals, and periodic service smoke tests use
executables and evaluated metadata from the Nix store. Remote-flake consumers
do not need a Nixstead checkout at `nixstead.host.repositoryPath` for these units.
