{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.arr;
in {
  config = lib.mkIf cfg.prowlarr.enable {
    services.prowlarr = {
      enable = true;
      settings.server = {
        bindaddress = serviceBindAddress "prowlarr";
        port = cfg.prowlarr.port;
      };
    };
  };
}
