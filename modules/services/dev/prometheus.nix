{
  config,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
  prometheusCfg = cfg.prometheus;
  exporters = prometheusCfg.exporters;
  stateDir = prometheusCfg.paths.stateDir;
  monitoredProxies = lib.filterAttrs (_: entry: entry.enabled && entry.proxy != null) config.nixstead.serviceRegistry;
  accessLogFile = id: "${toString exporters.nginxLog.accessLogDirectory}/nixstead-${id}.log";
  monitoredVirtualHosts = builtins.listToAttrs (lib.mapAttrsToList (id: entry: {
      name = entry.proxy.vhostKey or entry.settings.domain;
      value.extraConfig = lib.mkAfter ''
        access_log ${accessLogFile id} nixstead_metrics;
      '';
    })
    monitoredProxies);
  nginxLogNamespaces =
    lib.mapAttrsToList (id: entry: {
      name = id;
      namespace_label = "service_id";
      parser = "json";
      source.files = [(accessLogFile id)];
      metrics_override.prefix = "nginx";
      labels = {
        host = config.nixstead.host.hostName;
        service = entry.settings.domain;
      };
      histogram_buckets = exporters.nginxLog.histogramBuckets;
    })
    monitoredProxies;

  scrapeTarget = exporter: let
    address =
      if exporter.listenAddress == "0.0.0.0"
      then "127.0.0.1"
      else if exporter.listenAddress == "::"
      then "::1"
      else exporter.listenAddress;
    renderedAddress =
      if lib.hasInfix ":" address
      then "[${address}]"
      else address;
  in "${renderedAddress}:${toString exporter.port}";

  exporterScrape = name: exporter:
    lib.optional exporter.enable {
      job_name = name;
      static_configs = [
        {
          targets = [(scrapeTarget exporter)];
          labels.host = config.nixstead.host.hostName;
        }
      ];
    };

  generatedScrapeConfigs =
    [
      {
        job_name = "prometheus";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString prometheusCfg.port}"];
            labels.host = config.nixstead.host.hostName;
          }
        ];
      }
    ]
    ++ exporterScrape "node" exporters.node
    ++ exporterScrape "systemd" exporters.systemd
    ++ exporterScrape "nginxlog" exporters.nginxLog
    ++ exporterScrape "cadvisor" exporters.cadvisor;
in {
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = stateDir == null || (lib.hasPrefix "/var/lib/" stateDir && stateDir != "/var/lib/");
          message = "nixstead.services.dev.prometheus.paths.stateDir must be a directory below /var/lib when set.";
        }
        {
          assertion = !exporters.nginxLog.enable || !exporters.nginxLog.configureNginx || config.nixstead.services.nginx.enable;
          message = "The managed NGINX log exporter requires nixstead.services.nginx.enable, or set nginxLog.configureNginx = false and provide a compatible log.";
        }
      ];
    }

    (lib.mkIf prometheusCfg.enable {
      services.prometheus =
        {
          enable = true;
          port = prometheusCfg.port;
          listenAddress = serviceBindAddress "prometheus";
          globalConfig.scrape_interval = prometheusCfg.scrapeInterval;
          scrapeConfigs = generatedScrapeConfigs ++ prometheusCfg.extraScrapeConfigs;
        }
        // lib.optionalAttrs (stateDir != null) {
          stateDir = lib.removePrefix "/var/lib/" stateDir;
        };
    })

    (lib.mkIf exporters.node.enable {
      services.prometheus.exporters.node = {
        enable = true;
        inherit (exporters.node) listenAddress port openFirewall enabledCollectors disabledCollectors;
      };
    })

    (lib.mkIf exporters.systemd.enable {
      services.prometheus.exporters.systemd = {
        enable = true;
        inherit (exporters.systemd) listenAddress port openFirewall extraFlags;
      };
    })

    (lib.mkIf exporters.nginxLog.enable {
      services.prometheus.exporters.nginxlog = {
        enable = true;
        inherit (exporters.nginxLog) listenAddress port openFirewall;
        group = "nginx";
        settings.namespaces = nginxLogNamespaces;
      };

      systemd.services.prometheus-nginxlog-exporter = {
        after = lib.optional config.nixstead.services.nginx.enable "nginx.service";
        wants = lib.optional config.nixstead.services.nginx.enable "nginx.service";
      };
    })

    (lib.mkIf (exporters.nginxLog.enable && exporters.nginxLog.configureNginx) {
      services.nginx = {
        commonHttpConfig = ''
          log_format nixstead_metrics escape=json
            '{"request":"$request_method / HTTP/1.1","status":"$status",'
            '"body_bytes_sent":"$body_bytes_sent","request_length":"$request_length",'
            '"request_time":"$request_time","upstream_response_time":"$upstream_response_time"}';
        '';
        virtualHosts = monitoredVirtualHosts;
      };
    })

    (lib.mkIf exporters.cadvisor.enable {
      services.cadvisor = {
        enable = true;
        inherit (exporters.cadvisor) listenAddress port;
        extraOptions = exporters.cadvisor.extraOptions;
      };

      networking.firewall.allowedTCPPorts = lib.optional exporters.cadvisor.openFirewall exporters.cadvisor.port;
    })
  ];
}
