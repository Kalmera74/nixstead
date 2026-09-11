{
  config,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity.actualbudget;
in {
  config = lib.mkIf cfg.enable {
    services.actual = {
      enable = true;
      settings = {
        hostname = serviceBindAddress "actualbudget";
        inherit (cfg) port;
        dataDir = cfg.paths.dataDir;
      };
    };

    systemd.services.actual.unitConfig.RequiresMountsFor = lib.unique [
      config.services.actual.settings.dataDir
      config.services.actual.settings.serverFiles
      config.services.actual.settings.userFiles
    ];
  };
}
