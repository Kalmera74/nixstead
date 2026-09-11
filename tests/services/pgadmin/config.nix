{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  port = 23456;
  withDatabase =
    (mkSystem [
      ({pkgs, ...}: {
        nixstead.services.dev.pgadmin.enable = true;
        services.postgresql = {
          enable = true;
          package = pkgs.postgresql_17;
        };
      })
    ]).config;
  withNativeDatabase =
    (mkSystem [
      {
        nixstead.services.dev.pgadmin.enable = true;
        services.postgresql.enable = true;
      }
    ]).config;
  cfg =
    (mkSystem [
      {
        nixstead.services.dev.pgadmin = {
          enable = true;
          inherit port;
          domain = "fixture-pgadmin.example.test";
          initialEmail = "database-admin@example.test";
        };
      }
    ]).config;
in
  serviceContract {
    id = "pgadmin";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.pgadmin.enable;
  }
  // {
    unownedNativePathsRejected = lib.all (settings:
      lib.any (item: !item.assertion && lib.hasInfix "pgAdmin recovery requires" item.message)
      (mkSystem [
        {
          nixstead.services.dev.pgadmin.enable = true;
          services.pgadmin.settings = settings;
        }
      ]).config.assertions)
    [{DATA_DIR = "/srv/pgadmin";} {SQLITE_PATH = "/srv/accounts.db";} {STORAGE_DIR = "/srv/pgadmin-files";} {SQLITE_PATH = "/var/lib/pgadmin/../../accounts.db";} {CONFIG_DATABASE_URI = "sqlite:////srv/external.db";}];
    nativeDataRoot = cfg.services.pgadmin.settings.DATA_DIR == "/var/lib/pgadmin";
    nativeDatabasePath = cfg.services.pgadmin.settings.SQLITE_PATH == "/var/lib/pgadmin/pgadmin4.db";
    backupIncludesAccountState = cfg.nixstead.serviceRegistry.pgadmin.backup.paths == ["/var/lib/pgadmin"];
    accountDatabaseRequired = cfg.nixstead.serviceRegistry.pgadmin.backup.requiredFiles == ["pgadmin4.db"];
    customDatabaseRequired =
      (mkSystem [
        {
          nixstead.services.dev.pgadmin.enable = true;
          services.pgadmin.settings.SQLITE_PATH = "/var/lib/pgadmin/fixture.db";
        }
      ]).config.nixstead.serviceRegistry.pgadmin.backup.requiredFiles
      == ["fixture.db"];
    backupStopsApplication = cfg.nixstead.serviceRegistry.pgadmin.backup.units == ["pgadmin.service"];
    dynamicUserRestoration = cfg.nixstead.serviceRegistry.pgadmin.backup.dynamicUser && cfg.systemd.services.pgadmin.serviceConfig.DynamicUser;
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.pgadmin.port = 70000;}]).config.nixstead.services.dev.pgadmin.port).success;

    nativeListener = cfg.services.pgadmin.port == port && cfg.services.pgadmin.settings.DEFAULT_SERVER == "127.0.0.1";
    localBootstrapDomainAllowed = cfg.services.pgadmin.settings.ALLOW_SPECIAL_EMAIL_DOMAINS == ["local"];
    bootstrapEmail = cfg.services.pgadmin.initialEmail == "database-admin@example.test";
    bootstrapPasswordPath = cfg.services.pgadmin.initialPasswordFile == "/run/secrets/devdb/pgadmin/initialPassword";
    passwordRestartsService = cfg.sops.secrets."devdb/pgadmin/initialPassword".restartUnits == ["pgadmin.service"];
    nativeDatabasePackagePreserved = lib.hasPrefix "17." withNativeDatabase.services.postgresql.package.version;
    databasePackageSelectionPreserved = lib.hasPrefix "17." withDatabase.services.postgresql.package.version && builtins.isString withDatabase.system.build.toplevel.drvPath;
    databaseNotImplicitlyEnabled = !cfg.services.postgresql.enable;
  }
