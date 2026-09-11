# mergerfs

mergerfs combines configured NAS data disks into one directory without changing
their underlying filesystems. Nixstead mounts the pool at
`nixstead.services.nas.tankMount` and creates common Media, Public, Backup, Backups,
and Appdata directories.

## Enable and configure

```nix
nixstead.services.nas = {
  enable = true;
  mergerfs.enable = true;
  tankMount = "/srv/nas";
  disks.data = [
    {
      name = "data1";
      device = "/dev/disk/by-uuid/REPLACE_ME";
      mountPoint = "/mnt/data1";
      fsType = "ext4";
    }
  ];
};
```

The pool uses the most-free-space create policy and depends on all data-disk
mounts.

## Credentials and operation

mergerfs provides no credentials or web UI. Verify the pool with
`findmnt /srv/nas` and inspect the generated mount unit before storing data.

## State and recovery boundary

The mergerfs pool is a view over named data-disk filesystems. Data disks own the
file bytes; the merged directory does not create an independent backup copy.
Preserve disk mapping and stable file ownership in configuration, and keep an
independent backup outside the pool for any promised disaster recovery.

The disposable-disk runtime test mounts three native filesystems and the mergerfs
pool, then writes and reads one exact marker through the pool. SnapRAID parity
maintenance, repair, missing-mount behavior, restart/reboot and independent
archive recovery remain outside this fast smoke. Serving recovered bytes over
Samba belongs to the separate NAS/sharing interaction.
