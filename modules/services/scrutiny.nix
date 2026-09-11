{
  config,
  lib,
  serviceBindAddress,
  serviceOptionFromRegistry,
  serviceRegistry,
  ...
}: let
  cfg = config.nixstead.services.scrutiny;
  fixedPathOption = default: description:
    lib.mkOption {
      type = lib.types.path;
      inherit default description;
      readOnly = true;
    };
in {
  options.nixstead.services.scrutiny = serviceOptionFromRegistry "scrutiny" {
    pathOptions = {
      dataDir = fixedPathOption "/var/lib/scrutiny" "Native Scrutiny state directory.";
      influxdbDir = fixedPathOption "/var/lib/influxdb2" "Native InfluxDB state directory used by Scrutiny.";
    };
    extraOptions.influxdbPort = lib.mkOption {
      type = lib.types.port;
      default = serviceRegistry.scrutiny.defaults.influxdbPort;
      description = "Loopback InfluxDB port used by Scrutiny.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.scrutiny = {
      enable = true;
      influxdb.enable = true;
      settings = {
        web = {
          listen = {
            host = serviceBindAddress "scrutiny";
            inherit (cfg) port;
          };
          influxdb = {
            host = "127.0.0.1";
            port = cfg.influxdbPort;
          };
        };
      };
      collector = {
        enable = true;
        schedule = "daily";
        settings.host.id = config.nixstead.host.hostName;
      };
    };

    services.influxdb2.settings."http-bind-address" = "127.0.0.1:${toString cfg.influxdbPort}";
  };
}
