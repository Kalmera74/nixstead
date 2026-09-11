# Templates

This directory contains public flake templates exported by the root flake.

The `host` template is a small external-consumer starter that imports
`nixosModules.default` from this repository and keeps machine-specific settings
in the consumer's own flake. Its Nixstead input follows the consumer's Nixpkgs
revision.

Initialize it locally:

```bash
nix flake init -t path:.#host
```

Or from GitHub:

```bash
nix flake init -t github:Kalmera74/nixstead#host
```

Templates must remain generic: do not copy real hardware, storage, network, or
secret values into them. See [Installation](../docs/installation.md).
