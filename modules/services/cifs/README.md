# CIFS client

`cifs.nix` defines optional SMB/CIFS client mounts. It is intentionally
path-agnostic: the host declares every share source, mount point, and any
share-specific options.

```nix
{...}: {
  nixstead.services.cifs = {
    enable = true;
    shares = {
      media = {
        source = "//192.168.1.30/media";
        mountPoint = "/mnt/media";
      };
      appdata = {
        source = "//192.168.1.30/appdata";
        mountPoint = "/mnt/appdata";
        options = ["noperm" "dynperm"];
      };
      public = {
        source = "//192.168.1.30/public";
        mountPoint = "/mnt/public";
      };
    };
  };
};
```

Share names are arbitrary; there are no required media, appdata, public, or
downloads roles. Services retain their own defaults until the host explicitly
references a share, for example
`config.nixstead.services.cifs.shares.media.mountPoint`, from one of its typed path
options. CIFS generates `fileSystems` from the same definitions and rejects
duplicate mount points.

Credentials are loaded from the `cifs` secret domain and written to a root-only
runtime file. CIFS is intentionally excluded from presets because its server,
share names, and mount points are machine-specific.

See [Storage and backups](../../../docs/storage-backups.md).
