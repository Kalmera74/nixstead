# Local NAS stack

This directory implements an optional local storage pool:

- `disks.nix` defines typed data/parity device lists;
- `mergerfs.nix` combines data mounts at `tankMount`;
- `snapraid.nix` configures scheduled parity sync/scrub; and
- `samba.nix` publishes the tank and common subdirectories.

```nix
nixstead.services.nas = {
  enable = true;
  mergerfs.enable = true;
  snapraid.enable = true;
  samba.enable = true;
  tankMount = "/srv/nas";
  disks = {
    data = [
      { name = "data1"; device = "/dev/disk/by-id/<data-disk>"; mountPoint = "/srv/nas-data1"; fsType = "ext4"; }
    ];
  };
};
```

The disk lists default to empty. Define stable, verified device paths for the
actual machine before enabling this stack. The setup wizard discovers disks and
collects these values interactively, but it never partitions or formats them.
Samba exports no directories by default. Select authenticated shares explicitly
with `nixstead.services.nas.samba.shares`; see [the Samba guide](../../../docs/services/samba.md).

See [Storage and backups](../../../docs/storage-backups.md).
