{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.arr;
in {
  config = lib.mkIf cfg.readarr.enable {
    services.readarr = {
      enable = true;
      settings.server = {
        bindaddress = serviceBindAddress "readarr";
        port = cfg.readarr.port;
      };
    };
    users.users.readarr.extraGroups = [config.nixstead.host.groups.media];
  };
}
