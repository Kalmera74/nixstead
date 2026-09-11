# Modules

This directory contains reusable NixOS modules.

```text
modules/
├── core/       typed project options and registry resolution
├── hardware/   optional hardware capabilities
├── programs/   independently imported package/tool groups
├── services/   homelab services, presets, and integrations
└── system/     shared user, locale, networking, and Nix behavior
```

`base.nix` imports core, hardware, and system modules. `default.nix` imports
`base.nix` plus all services and is the normal complete entry point.

External consumers should use exports from `flake.nix`, for example:

```nix
imports = [nixstead.nixosModules.default];
```

Internal file paths are organization details rather than the public API. See
[Architecture](../docs/architecture.md) and
[Public module API](../docs/module-api.md).
