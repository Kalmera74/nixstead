{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.arr;
in {
  config = lib.mkIf cfg.bazarr.enable {
    services.bazarr = {
      enable = true;
      listenPort = cfg.bazarr.port;
    };
    users.users.bazarr.extraGroups = [config.nixstead.host.groups.media];
    # Bazarr uses Dynaconf's supported nested environment overrides.
    systemd.services.bazarr.environment.DYNACONF_GENERAL__IP = serviceBindAddress "bazarr";
  };
}
