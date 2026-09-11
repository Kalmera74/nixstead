{config, ...}: {
  imports = [
    ./audio.nix
    ./bluetooth.nix
    ./disks.nix
  ];

  hardware.enableAllFirmware = config.nixstead.host.hardware.enableAllFirmware;
}
