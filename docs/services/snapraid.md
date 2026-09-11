# SnapRAID

SnapRAID adds scheduled parity protection to the NAS data disks. It is not
real-time RAID: sync records the current data state, and scrub verifies stored
blocks. Nixstead schedules sync every six hours and scrub daily.

## Enable and configure

```nix
nixstead.services.nas = {
  enable = true;
  snapraid.enable = true;
  disks.data = [
    {
      name = "data1";
      device = "/dev/disk/by-uuid/DATA_UUID";
      mountPoint = "/mnt/data1";
      fsType = "ext4";
    }
  ];
  disks.parity = [
    {
      device = "/dev/disk/by-uuid/PARITY_UUID";
      mountPoint = "/mnt/parity1";
      fsType = "ext4";
    }
  ];
};
```

At least one data and parity disk are required.

## Credentials and operation

SnapRAID has no credentials or web UI. Review device identifiers carefully,
monitor its sync and scrub timers, and use the upstream recovery procedure
before replacing or restoring failed disks.

## State and recovery boundary

SnapRAID owns parity and content metadata for its declared data disks. Its sync,
scrub and deleted/corrupt-file repair flows require disposable-disk tests with
independently known bytes. Parity repair is not an independent backup and does not
cover every multi-disk loss or every unsynchronized change.

Preserve disk mappings and content metadata consistently. The disposable NAS
runtime test checks that the configured data, parity and mergerfs mounts start
and that the pool can store one exact marker. It does not exercise SnapRAID
sync, scrub or repair. Any promised independent backup of data disks still needs
a separate archive/restore fixture; the Samba access test does not provide one.
