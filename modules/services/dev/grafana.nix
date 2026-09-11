{
  config,
  host,
  lib,
  secretPath,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
  provisioning = cfg.grafana.provisioning;
  prometheusUrl =
    if provisioning.prometheus.url != null
    then provisioning.prometheus.url
    else "http://127.0.0.1:${toString cfg.prometheus.port}";
  lokiUrl =
    if provisioning.loki.url != null
    then provisioning.loki.url
    else "http://127.0.0.1:${toString cfg.loki.port}";
  dataSources =
    lib.optional provisioning.prometheus.enable {
      name = "Prometheus";
      type = "prometheus";
      uid = "prometheus";
      url = prometheusUrl;
      access = "proxy";
      isDefault = true;
      editable = true;
      jsonData = {
        prometheusType = "Prometheus";
        prometheusVersion = "3.0.0";
        timeInterval = cfg.prometheus.scrapeInterval;
      };
    }
    ++ lib.optional provisioning.loki.enable {
      name = "Loki";
      type = "loki";
      uid = "loki";
      url = lokiUrl;
      access = "proxy";
      editable = true;
    }
    ++ provisioning.extraDataSources;
  dashboardProviders =
    lib.optional provisioning.serviceUsageDashboard.enable {
      name = "nixstead-service-monitoring";
      type = "file";
      disableDeletion = false;
      allowUiUpdates = true;
      updateIntervalSeconds = 30;
      options.path = ./dashboards/service-usage;
    }
    ++ lib.optional provisioning.arrDashboard.enable {
      name = "nixstead-arr-monitoring";
      type = "file";
      disableDeletion = false;
      allowUiUpdates = true;
      updateIntervalSeconds = 30;
      options.path = ./dashboards/arr;
    }
    ++ lib.imap0 (index: path: {
      name = "nixstead-custom-${toString index}";
      type = "file";
      disableDeletion = false;
      allowUiUpdates = true;
      updateIntervalSeconds = 30;
      options.path = path;
    })
    provisioning.dashboardPaths;
in {
  config = lib.mkIf cfg.grafana.enable {
    sops.secrets = {
      "devdb/grafana/adminUser" = {
        owner = "grafana";
        restartUnits = ["grafana.service"];
      };
      "devdb/grafana/adminPassword" = {
        owner = "grafana";
        restartUnits = ["grafana.service"];
      };
      "devdb/grafana/secretKey" = {
        owner = "grafana";
        restartUnits = ["grafana.service"];
      };
    };

    systemd.services.grafana.unitConfig.RequiresMountsFor = [config.services.grafana.dataDir];

    services.grafana =
      {
        enable = true;
        settings = {
          server = {
            domain = config.nixstead.services.dev.grafana.domain;
            http_addr = serviceBindAddress "grafana";
            http_port = config.nixstead.services.dev.grafana.port;
          };
          users = {
            allow_sign_up = false;
          };
          security = {
            admin_user = "$__file{${secretPath "devdb/grafana/adminUser"}}";
            admin_password = "$__file{${secretPath "devdb/grafana/adminPassword"}}";
            secret_key = "$__file{${secretPath "devdb/grafana/secretKey"}}";
          };
        };
        provision = lib.mkIf provisioning.enable {
          enable = true;
          datasources.settings = {
            apiVersion = 1;
            prune = false;
            datasources = dataSources;
          };
          dashboards.settings = {
            apiVersion = 1;
            providers = dashboardProviders;
          };
        };
      }
      // lib.optionalAttrs (cfg.grafana.paths.dataDir != null) {
        dataDir = cfg.grafana.paths.dataDir;
      };
  };
}
