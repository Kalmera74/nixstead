{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.arr;
in {
  config = lib.mkIf cfg.radarr.enable {
    services.radarr = {
      enable = true;
      settings.server = {
        bindaddress = serviceBindAddress "radarr";
        port = cfg.radarr.port;
      };
    };
    users.users.radarr.extraGroups = [config.nixstead.host.groups.media];
  };
}
