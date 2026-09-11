# Hosts

The public repository intentionally contains no personal machine
configuration. This directory remains the target for the optional
repository-local workflow used by clones and forks.

Each subdirectory represents one concrete NixOS machine. A directory containing
`default.nix` is discovered automatically by the root flake and exported as
`nixosConfigurations.<directory-name>`.

A normal host contains:

```text
hosts/example/
├── README.md
├── default.nix
└── hardware-configuration.nix
```

`default.nix` owns machine identity, program imports, `system.stateVersion`, a
service preset, explicit service overrides, hardware choices, and bootloader
settings. `hardware-configuration.nix` is generated for that machine and must
declare `nixpkgs.hostPlatform`.

Create a host with:

```bash
./setup.sh --generate-only
```

Do not copy another machine's hardware, disk, or bootloader configuration
blindly. See [Configuring a host](../docs/configuration.md).
