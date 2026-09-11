# Services

This directory contains homelab service options, implementations, preset
selection, and registry-driven integrations.

Key files:

- `services.nix` imports the complete service catalog.
- `registry.nix` aggregates service identity and repeated integration metadata.
- `registry/` stores stack-aligned metadata fragments and shared constructors.
- `presets.nix` implements `nixstead.preset` from registry membership.
- `registry-integrations.nix` renders firewall exposure.
- `container-image-overrides.nix` maps registry-keyed host image pins to typed
  service image options.
- `external.nix` defines Pi-hole, Proxmox, and TrueNAS integration options.

Stack directories contain wrapper options and concrete service modules. Nginx
and Homepage have their own registry renderers.

Example selection:

```nix
nixstead.preset = "media-server";
nixstead.services.arr.lidarr.enable = false;
nixstead.services.media.immich.enable = true;
```

When adding a service, prefer an existing stack. Create a new stack only for at
least two related services; otherwise use a standalone
`modules/services/<service>.nix` module and `nixstead.services.<service>` option. Put
shared metadata in the matching `registry/` fragment and implementation
behavior in the appropriate module. See
[Central service registry](../../docs/service-registry.md) and
[Services](../../docs/services.md). User-facing setup, credential, storage, and
troubleshooting instructions live in the
[per-service guides](../../docs/services/README.md).
