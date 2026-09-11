{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.arr;
in {
  config = lib.mkIf cfg.lidarr.enable {
    services.lidarr = {
      enable = true;
      settings.server = {
        bindaddress = serviceBindAddress "lidarr";
        port = cfg.lidarr.port;
      };
    };
    users.users.lidarr.extraGroups = [config.nixstead.host.groups.media];
  };
}
