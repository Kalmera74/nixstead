# Hardware modules

These modules implement optional machine capabilities selected through
`nixstead.host.hardware`.

- `audio.nix` enables PipeWire audio support.
- `bluetooth.nix` enables and configures Bluetooth.
- `disks.nix` configures the optional swap file/device.
- `hardware.nix` imports the group and controls firmware support.

Example:

```nix
nixstead.host.hardware = {
  audio.enable = true;
  bluetooth.enable = false;
  enableAllFirmware = true;
  gpu.acceleration = "cuda";
  swap = {
    enable = true;
    device = "/swapfile";
    sizeMiB = 16384;
  };
};
```

Hardware defaults are conservative. Physical filesystems, bootloaders, and
detected devices remain in each host's generated hardware configuration and
host file.
