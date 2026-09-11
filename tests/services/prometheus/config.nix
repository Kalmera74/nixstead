{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  port = 23456;
  cfg =
    (mkSystem [
      {
        nixstead.services.dev.prometheus = {
          enable = true;
          inherit port;
          domain = "fixture-prometheus.example.test";
          paths.stateDir = "/var/lib/custom-metrics";
          scrapeInterval = "37s";
          extraScrapeConfigs = [
            {
              job_name = "fixture";
              static_configs = [{targets = ["127.0.0.1:19000"];}];
            }
          ];
          exporters.node = {
            enable = true;
            port = 19100;
            enabledCollectors = ["systemd"];
          };
        };
      }
    ]).config;
in
  serviceContract {
    id = "prometheus";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.prometheus.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.prometheus.port = 70000;}]).config.nixstead.services.dev.prometheus.port).success;

    nativeListener = cfg.services.prometheus.port == port && cfg.services.prometheus.listenAddress == "127.0.0.1";
    nativeStatePath = cfg.services.prometheus.stateDir == "custom-metrics";
    scrapeInterval = cfg.services.prometheus.globalConfig.scrape_interval == "37s";
    customScrapeJob = lib.any (job: job.job_name == "fixture" && (builtins.head job.static_configs).targets == ["127.0.0.1:19000"]) cfg.services.prometheus.scrapeConfigs;
    exporterConfigured = cfg.services.prometheus.exporters.node.enable && cfg.services.prometheus.exporters.node.port == 19100;
    exporterNotExposed = !(lib.elem 19100 cfg.networking.firewall.allowedTCPPorts);
    disposableHistoryHasNoBackupClaim = cfg.nixstead.serviceRegistry.prometheus.backup == null;
    invalidStateRootRejected = lib.any (item: !item.assertion && lib.hasInfix "below /var/lib" item.message) (mkSystem [{nixstead.services.dev.prometheus.paths.stateDir = "/srv/metrics";}]).config.assertions;
    managedLogDependencyRejected = lib.any (item: !item.assertion && lib.hasInfix "managed NGINX log exporter" item.message) (mkSystem [{nixstead.services.dev.prometheus.exporters.nginxLog.enable = true;}]).config.assertions;
  }
