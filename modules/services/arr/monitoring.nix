{
  config,
  options,
  lib,
  serviceRegistry,
  ...
}: let
  cfg = config.nixstead.services.arr.monitoring;
  supported = lib.filterAttrs (_: entry: entry.metrics != null) serviceRegistry;
  selected = lib.filterAttrs (id: _: cfg.services.${id}.enable && config.nixstead.serviceRegistry.${id}.enabled) supported;
  ports = map (id: cfg.services.${id}.port) (lib.attrNames selected);
  exporterOptions = options.services.prometheus.exporters.type.getSubOptions [];
  availableExporters = lib.genAttrs (lib.attrNames (lib.filterAttrs (_: option: (option.type.name or "") == "submodule" && (option.visible or true) != false) exporterOptions)) (name: config.services.prometheus.exporters.${name});
  otherExporterPorts = map (exporter: exporter.port) (lib.attrValues (lib.filterAttrs (name: exporter: builtins.isAttrs exporter && exporter ? enable && exporter ? port && exporter.enable && !lib.elem name (map (entry: entry.metrics.exporter) (lib.attrValues selected))) availableExporters));
  scrapeHost = address:
    if address == "0.0.0.0"
    then "127.0.0.1"
    else if address == "::"
    then "[::1]"
    else if lib.hasInfix ":" address
    then "[${address}]"
    else address;
  applicationPorts =
    lib.concatMap (entry: map (setting: entry.settings.${setting}) (entry.listeners.settingsTcpPorts or []))
    (lib.attrValues (lib.filterAttrs (_: entry: entry.enabled) config.nixstead.serviceRegistry));
in {
  options.nixstead.services.arr.monitoring = {
    enable = lib.mkEnableOption "registry-generated application exporters";
    services =
      lib.mapAttrs (id: entry: {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = cfg.enable;
          description = "Export ${entry.name} application metrics when enabled.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = entry.metrics.port;
          description = "${entry.name} exporter TCP port.";
        };
        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Exporter listener. Remote access also requires an explicit firewall rule.";
        };
      })
      supported;
  };
  config = lib.mkIf (selected != {}) {
    nixstead.services.arr.credentials.enable = lib.mkDefault true;
    nixstead.services.arr.credentials.consumers = lib.mapAttrs (_: entry: ["prometheus-${entry.metrics.exporter}-exporter.service"]) selected;
    assertions = [
      {
        assertion = config.nixstead.services.arr.credentials.enable;
        message = "ARR monitoring requires shared runtime credentials.";
      }
      {
        assertion = lib.length ports == lib.length (lib.unique ports) && !lib.any (port: lib.elem port (applicationPorts ++ otherExporterPorts)) ports;
        message = "ARR exporter ports must be unique and separate from application ports.";
      }
    ];
    services.prometheus.exporters = lib.mapAttrs' (id: entry:
      lib.nameValuePair entry.metrics.exporter ({
          enable = true;
          inherit (cfg.services.${id}) port listenAddress;
          openFirewall = false;
        }
        // (
          if entry.metrics.exporter == "sabnzbd"
          then {
            servers = [
              {
                baseUrl = "http://127.0.0.1:${toString config.nixstead.serviceRegistry.${id}.settings.port}";
                apiKeyFile = "/run/nixstead-credentials/${id}/api-key";
              }
            ];
          }
          else {
            url = "http://127.0.0.1:${toString config.nixstead.serviceRegistry.${id}.settings.port}";
            apiKeyFile = "/run/nixstead-credentials/${id}/api-key";
            environment = {
              INTERFACE = cfg.services.${id}.listenAddress;
              ENABLE_ADDITIONAL_METRICS = "false";
              DISABLE_QUALITY_METRICS = "true";
              DISABLE_EPISODE_METRICS = "true";
              DISABLE_ALBUM_METRICS = "true";
              DISABLE_HISTORY_METRICS = "true";
              DISABLE_WANTED_METRICS = "true";
              ENABLE_UNKNOWN_QUEUE_ITEMS = "false";
            };
          }
        )))
    selected;
    services.prometheus.scrapeConfigs = lib.mkIf config.services.prometheus.enable (lib.mapAttrsToList (id: entry: {
        job_name = "nixstead-${id}";
        scrape_interval = entry.metrics.scrapeInterval;
        scrape_timeout = "30s";
        static_configs = [
          {
            targets = ["${scrapeHost cfg.services.${id}.listenAddress}:${toString cfg.services.${id}.port}"];
            labels.service = id;
          }
        ];
      })
      selected);
  };
}
