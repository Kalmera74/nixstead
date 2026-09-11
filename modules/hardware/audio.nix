{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixstead.host.hardware.audio;
in {
  config = lib.mkIf cfg.enable {
    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    environment.systemPackages = with pkgs; [
      pulseaudioFull
      wiremix
    ];
  };
}
