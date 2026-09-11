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
        nixstead.services.dev.postgresql = {
          enable = true;
          inherit port;
          domain = "fixture-postgresql.example.test";
        };
      }
    ]).config;
  custom =
    (mkSystem [
      {
        nixstead.services.dev.postgresql.enable = true;
        services.postgresql.dataDir = "/srv/postgresql";
      }
    ]).config;
in
  serviceContract {
    id = "postgresql";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.postgresql.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.postgresql.port = 70000;}]).config.nixstead.services.dev.postgresql.port).success;

    nativeListener = cfg.services.postgresql.settings.port == port && cfg.services.postgresql.settings.listen_addresses == "127.0.0.1";
    runtimeCredentials = lib.elem "/run/secrets/rendered/postgresql-admin.env" cfg.systemd.services.postgresql.serviceConfig.EnvironmentFile;
    runtimePasswordPlaceholder = lib.hasInfix cfg.sops.placeholder."devdb/postgresql/rootPassword" cfg.sops.templates."postgresql-admin.env".content;
    sqlQuotesIdentifiersAndPasswords = lib.hasInfix "CREATE ROLE %I WITH LOGIN SUPERUSER PASSWORD %L" cfg.systemd.services.postgresql.postStart;
    customDatabasePath = custom.services.postgresql.dataDir == "/srv/postgresql";
    backupUsesNativeData = custom.nixstead.serviceRegistry.postgresql.backup.paths == ["/srv/postgresql"];
    backupUsesSqlHandler = cfg.nixstead.serviceRegistry.postgresql.backup.database == "postgresql";
    backupUsesNativePort = cfg.nixstead.serviceRegistry.postgresql.backup.databasePort == port;
    bootstrapUsesNativePort = lib.hasInfix "--port ${toString port} --dbname postgres" cfg.systemd.services.postgresql.postStart;
  }
