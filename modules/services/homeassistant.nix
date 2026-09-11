{
  config,
  lib,
  runtimePathOption,
  serviceBindAddress,
  serviceOptionFromRegistry,
  ...
}: let
  cfg = config.nixstead.services.homeassistant;
in {
  options.nixstead.services.homeassistant = serviceOptionFromRegistry "homeassistant" {
    pathOptions.dataDir = runtimePathOption "/var/lib/hass" "Absolute directory containing Home Assistant configuration and state.";
  };

  config = lib.mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
      configDir = cfg.paths.dataDir;
      config = {
        default_config = {};
        http = {
          server_host = serviceBindAddress "homeassistant";
          server_port = cfg.port;
          use_x_forwarded_for = true;
          trusted_proxies = [
            "127.0.0.1"
            "::1"
          ];
        };
      };
    };

    systemd.services.home-assistant.unitConfig.RequiresMountsFor = cfg.paths.dataDir;
  };
}
