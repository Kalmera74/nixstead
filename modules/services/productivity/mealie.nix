{
  config,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity.mealie;
in {
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.systemd.services.mealie.environment.DATA_DIR == cfg.paths.dataDir;
        message = "Mealie recovery requires native DATA_DIR to remain /var/lib/mealie.";
      }
    ];

    services.mealie = {
      enable = true;
      listenAddress = serviceBindAddress "mealie";
      inherit (cfg) port;
      settings = {
        BASE_URL = "https://${cfg.domain}";
        ALLOW_SIGNUP = "false";
        TZ = config.nixstead.host.locale.timeZone;
      };
    };

    systemd.services.mealie.unitConfig.RequiresMountsFor = [cfg.paths.dataDir];
  };
}
