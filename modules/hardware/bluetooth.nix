{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixstead.host.hardware.bluetooth;
in {
  config = lib.mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;

      settings = {
        General = {
          Name = config.nixstead.host.hostName;
          ControllerMode = "dual";
          FastConnectable = "true";
          Experimental = "true";
          Enable = "Source,Sink,Media,Socket";
        };
        Policy.AutoEnable = "true";
        LE.EnableAdvMonInterleaveScan = "true";
      };
    };

    environment.systemPackages = [pkgs.bluez];
  };
}
