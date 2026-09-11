{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.media;
in {
  config = lib.mkIf cfg.komga.enable {
    services.komga = {
      enable = true;
      settings = {
        server = {
          address = serviceBindAddress "komga";
          port = config.nixstead.services.media.komga.port;
        };
      };
    };
  };
}
