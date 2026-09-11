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
        nixstead.services.productivity.miniflux = {
          enable = true;
          inherit port;
          domain = "fixture-miniflux.example.test";
          adminCredentialsFile = "/run/credentials/miniflux-admin";
        };
        services.postgresql.settings.port = 25432;
      }
    ]).config;
in
  serviceContract {
    id = "miniflux";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.services.miniflux.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.miniflux.port = 70000;}]).config.nixstead.services.productivity.miniflux.port).success;

    nativeListener = cfg.services.miniflux.config.LISTEN_ADDR == "127.0.0.1:${toString port}";
    credentialOverride = cfg.services.miniflux.adminCredentialsFile == "/run/credentials/miniflux-admin";
    noCompetingGenerator = !(cfg.systemd.services ? miniflux-bootstrap-credentials);
    databaseDependency = cfg.services.postgresql.enable && lib.elem "miniflux-database-setup.service" cfg.systemd.services.miniflux.requires;
    databaseOwnerRepair = lib.hasInfix "ALTER DATABASE miniflux OWNER TO miniflux" cfg.systemd.services.miniflux-database-setup.script;
    nativeDatabasePort = cfg.services.miniflux.config.DATABASE_URL == "user=miniflux host=/run/postgresql port=25432 dbname=miniflux";
    databaseBootstrapPort = lib.hasInfix "--port 25432" cfg.systemd.services.miniflux-database-setup.script;
    backupDatabasePort = cfg.nixstead.serviceRegistry.miniflux.backup.databasePort == 25432;
    backupIncludesDatabase = cfg.nixstead.serviceRegistry.miniflux.backup.database == "postgresql" && cfg.nixstead.serviceRegistry.miniflux.backup.databaseName == "miniflux";
    fixedPathRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.miniflux.paths.dataDir = "/srv/miniflux";}]).config.nixstead.services.productivity.miniflux.paths.dataDir).success;
  }
