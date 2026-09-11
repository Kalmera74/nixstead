# System modules

These modules provide the shared NixOS foundation imported by `modules/base.nix`.

- `locale.nix` maps `nixstead.host.locale` into NixOS locale/time settings.
- `networking.nix` sets the hostname, enables NetworkManager/OpenSSH, applies
  `nixstead.host.ssh`, and uses the configured SSH port for both sshd and the firewall.
- `nix.nix` enables flakes, store optimization, garbage collection, unfree
  packages, zram swap, and shared overlays.
- `service-smoke-tests.nix` schedules read-only runtime checks for enabled
  registry services using Nix-store metadata and executables.
- `user.nix` creates the selected normal user and shared media group, and
  publishes the common generated-files path to SOPS-aware login sessions.
- `system.nix` imports the group.

Example host values:

```nix
nixstead.host = {
  hostName = "homelab";
  locale.timeZone = "UTC";
  user = {
    enable = true;
    name = "admin";
  };
};
```

Do not set `system.stateVersion` here; each host owns its original value.
