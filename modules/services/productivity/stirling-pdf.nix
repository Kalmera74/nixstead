{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity;
in {
  config = lib.mkIf cfg.stirlingpdf.enable {
    services.stirling-pdf = {
      enable = true;
      environment = {
        SERVER_PORT = toString config.nixstead.services.productivity.stirlingpdf.port;
        SERVER_ADDRESS = serviceBindAddress "stirlingpdf";
      };
    };
  };
}
