{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.host.hardware.swap;
in {
  swapDevices = lib.mkIf cfg.enable [
    {
      device = cfg.device;
      size = cfg.sizeMiB;
    }
  ];
}
