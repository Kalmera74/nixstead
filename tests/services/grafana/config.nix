{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  port = 23456;
  arrDashboard = builtins.fromJSON (builtins.readFile ../../../modules/services/dev/dashboards/arr/arr-application-overview.json);
  cfg =
    (mkSystem [
      {
        nixstead.services.dev.grafana = {
          enable = true;
          inherit port;
          domain = "fixture-grafana.example.test";
          paths.dataDir = "/srv/grafana";
          provisioning = {
            enable = true;
            prometheus = {
              enable = true;
              url = "http://metrics.example:9090";
            };
            loki = {
              enable = true;
              url = "http://logs.example:3100";
            };
          };
        };
      }
    ]).config;
  dashboardsCfg =
    (mkSystem [
      {
        nixstead.services.dev.grafana = {
          enable = true;
          provisioning = {
            enable = true;
            serviceUsageDashboard.enable = true;
            arrDashboard.enable = true;
          };
        };
      }
    ]).config;
in
  serviceContract {
    id = "grafana";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.grafana.enable;
  }
  // {
    backupFollowsNativeState = cfg.nixstead.serviceRegistry.grafana.backup.paths == ["/srv/grafana"];
    backupStopsWriter = cfg.nixstead.serviceRegistry.grafana.backup.units == ["grafana.service"];
    backupRequiresNativeDatabase = cfg.nixstead.serviceRegistry.grafana.backup.requiredFiles == ["data/grafana.db"] && cfg.services.grafana.settings.database.path == "/srv/grafana/data/grafana.db";
    mountRequired = lib.elem "/srv/grafana" cfg.systemd.services.grafana.unitConfig.RequiresMountsFor;
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.grafana.port = 70000;}]).config.nixstead.services.dev.grafana.port).success;

    nativeListener = cfg.services.grafana.settings.server.http_port == port && cfg.services.grafana.settings.server.http_addr == "127.0.0.1";
    nativeDataPath = cfg.services.grafana.dataDir == "/srv/grafana";
    registrationDisabled = !cfg.services.grafana.settings.users.allow_sign_up;
    administratorFile = cfg.services.grafana.settings.security.admin_password == "$__file{/run/secrets/devdb/grafana/adminPassword}";
    encryptionKeyFile = cfg.services.grafana.settings.security.secret_key == "$__file{/run/secrets/devdb/grafana/secretKey}";
    secretOwnedByService = cfg.sops.secrets."devdb/grafana/secretKey".owner == "grafana";
    datasourceOverrides = map (source: source.url) cfg.services.grafana.provision.datasources.settings.datasources == ["http://metrics.example:9090" "http://logs.example:3100"];
    builtInDashboardsAreOptIn = cfg.services.grafana.provision.dashboards.settings.providers == [];
    builtInDashboardsAreIndependent =
      map
      (provider: {
        inherit (provider) name;
        path = builtins.baseNameOf (toString provider.options.path);
      })
      dashboardsCfg.services.grafana.provision.dashboards.settings.providers
      == [
        {
          name = "nixstead-service-monitoring";
          path = "service-usage";
        }
        {
          name = "nixstead-arr-monitoring";
          path = "arr";
        }
      ];
    arrDashboardUsesExportarr =
      arrDashboard.uid
      == "nixstead-arr-overview"
      && lib.length arrDashboard.panels == 14
      && lib.hasInfix "exportarr_app_info" (builtins.toJSON arrDashboard);
  }
