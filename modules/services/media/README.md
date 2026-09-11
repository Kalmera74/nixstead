# Media stack

This directory contains Jellyfin, Seerr, Tdarr, Komga, Kavita,
Audiobookshelf, Kiwix, Immich, RomM, and TubeArchivist.

`media.nix` defines the parent/child option structure. Tdarr is split into
server and local-node implementation modules so either role can be selected.

```nix
nixstead.services.media = {
  enable = true;
  seerr.enable = false;
  tdarr = {
    server = true;
    node = true;
  };
};
```

Remote-backed paths are typed runtime options and have no CIFS dependency.
Configure them in the host module together with any CIFS shares before
activation. Native services retain their NixOS module defaults unless the host
sets the corresponding typed path in `nixstead.services.media`.

User-facing setup and initial-account instructions are indexed in the
[per-service guides](../../../docs/services/README.md).
