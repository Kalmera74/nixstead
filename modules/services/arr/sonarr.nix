{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.arr;
in {
  config = lib.mkIf cfg.sonarr.enable {
    services.sonarr = {
      enable = true;
      settings.server = {
        bindaddress = serviceBindAddress "sonarr";
        port = cfg.sonarr.port;
      };
    };
    users.users.sonarr.extraGroups = [config.nixstead.host.groups.media];
  };
}
