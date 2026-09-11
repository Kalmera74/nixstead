# Nixstead host template

This template creates a small consumer flake that imports Nixstead from GitHub.
Nix stores the upstream revision in `flake.lock`; this directory holds only the
new machine's configuration. Nixstead follows this flake's Nixpkgs input so
the module and host cannot silently use mismatched Nixpkgs revisions.

## Prepare it

1. Replace `my-host` in `flake.nix` and `configuration.nix` with the desired
   flake target and hostname.
2. Replace the placeholder network, user, and `nixstead.host.repositoryPath` values.
3. Keep `26.05` only for a new 26.05 installation; otherwise preserve the
   installed machine's original `system.stateVersion`.
4. Generate or copy `hardware-configuration.nix` and import it from
   `configuration.nix`.
5. Select a `nixstead.preset` and add explicit service overrides.

Generate hardware configuration on NixOS:

```bash
sudo nixos-generate-config --show-hardware-config \
  > hardware-configuration.nix
```

Add:

```nix
imports = [./hardware-configuration.nix];
```

Then validate and switch:

```bash
nix flake check
sudo nixos-rebuild switch --flake path:.#my-host
```

If selected services need credentials, enroll this host, create an encrypted
`secrets/my-host.yaml`, and enable the commented `nixstead.secrets` block in
`configuration.nix`. Follow the upstream
[secrets guide](https://github.com/Kalmera74/nixstead/blob/master/docs/secrets.md).

## Pin a different container version

`configuration.nix` conditionally imports the included `container-images.nix`.
Extend that plain attrset when a containerized service must differ from the
upstream registry default:

```nix
{
  "romm" = {
    "application" =
      "ghcr.io/rommapp/romm:5.2.1@sha256:<64 hexadecimal characters>";
  };
}
```

Both an exact tag and its registry digest are required.
`nixstead images` resolves and verifies the digest, guards
downgrades, generates this file, and validates the flake without activating
the system. See the upstream
[operations guide](https://github.com/Kalmera74/nixstead/blob/master/docs/operations.md#updating-oci-containers).
