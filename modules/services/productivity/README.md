# Productivity stack

This directory contains Paperless-ngx, Nextcloud, n8n, Stirling PDF, Seafile,
Wallabag, Linkwarden, SnapOtter, Mealie, Actual Budget, Miniflux, and SearXNG.

```nix
nixstead.services.productivity = {
  enable = true;
  nextcloud.enable = false;
  snapotter.enable = false;
};
```

The parent defaults all children on and the `full` preset selects the stack.
Applications have different storage and credential requirements; inspect their
registry entries, encrypted secret declarations, and concrete modules before enabling
them on important data.

The [per-service guides](../../../docs/services/README.md) document those
requirements and each application's first-login procedure.
