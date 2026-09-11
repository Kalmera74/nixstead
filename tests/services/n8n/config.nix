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
        nixstead.services.productivity.n8n = {
          enable = true;
          inherit port;
          domain = "fixture-n8n.example.test";
        };
      }
    ]).config;
  withEnvironment = environment:
    (mkSystem [
      {
        nixstead.services.productivity.n8n.enable = true;
        services.n8n.environment = environment;
      }
    ]).config;
  explicit = withEnvironment {
    DB_TYPE = "sqlite";
    DB_SQLITE_DATABASE = "database.sqlite";
  };
  external = withEnvironment {DB_TYPE = "postgresdb";};
  custom = withEnvironment {DB_SQLITE_DATABASE = "/srv/n8n/custom.sqlite";};
  fileSelected = withEnvironment {DB_TYPE_FILE = "/run/secrets/n8n-db-type";};
  fileDatabase = withEnvironment {DB_SQLITE_DATABASE_FILE = "/run/secrets/n8n-db-path";};
  environmentFile =
    (mkSystem [
      {
        nixstead.services.productivity.n8n.enable = true;
        systemd.services.n8n.serviceConfig.EnvironmentFile = "/run/secrets/n8n-environment";
      }
    ]).config;
  secretKey = withEnvironment {N8N_ENCRYPTION_KEY_FILE = "/run/secrets/n8n-key";};
  exposed =
    (mkSystem [
      {
        nixstead.services.productivity.n8n.enable = true;
        nixstead.host.network.exposure.services.n8n = "public";
      }
    ]).config;
in
  serviceContract {
    id = "n8n";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.services.n8n.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.n8n.port = 70000;}]).config.nixstead.services.productivity.n8n.port).success;

    nativeListener = cfg.services.n8n.environment.N8N_PORT == toString port && cfg.services.n8n.environment.N8N_LISTEN_ADDRESS == "127.0.0.1";
    exposedNativeListener = exposed.services.n8n.environment.N8N_LISTEN_ADDRESS == "0.0.0.0";
    secureCookies = cfg.services.n8n.environment.N8N_SECURE_COOKIE == "true";
    customWebhook = cfg.services.n8n.environment.WEBHOOK_URL == "https://fixture-n8n.example.test";
    backupIncludesWorkflowState = cfg.nixstead.serviceRegistry.n8n.backup.paths == ["/var/lib/n8n"];
    backupUsesDynamicOwnership = cfg.nixstead.serviceRegistry.n8n.backup.dynamicUser && cfg.nixstead.serviceRegistry.n8n.backup.owner == "root" && cfg.nixstead.serviceRegistry.n8n.backup.group == "root" && cfg.systemd.services.n8n.serviceConfig.DynamicUser == "true";
    backupRequiresConfigAndDefaultDatabase = cfg.nixstead.serviceRegistry.n8n.backup.requiredFiles == [".n8n/config" ".n8n/database.sqlite"];
    backupPreservesNativeWalBundle = (cfg.nixstead.serviceRegistry.n8n.backup.requiredSQLiteFiles or []) == [];
    backupRequiresNonemptyEncryptionMaterial =
      cfg.nixstead.serviceRegistry.n8n.backup.requiredJsonStrings
      == [
        {
          file = ".n8n/config";
          keys = ["encryptionKey"];
        }
      ];
    explicitDefaultDatabaseRequired = explicit.nixstead.serviceRegistry.n8n.backup.requiredFiles == [".n8n/config" ".n8n/database.sqlite"];
    externalDatabaseNotMisidentified = external.nixstead.serviceRegistry.n8n.backup.requiredFiles == [".n8n/config"];
    customDatabaseNotMisidentified = custom.nixstead.serviceRegistry.n8n.backup.requiredFiles == [".n8n/config"];
    runtimeDatabaseChoiceNotAssumed = fileSelected.nixstead.serviceRegistry.n8n.backup.requiredFiles == [".n8n/config"];
    runtimeDatabasePathNotAssumed = fileDatabase.nixstead.serviceRegistry.n8n.backup.requiredFiles == [".n8n/config"];
    runtimeEnvironmentDatabaseNotAssumed = environmentFile.nixstead.serviceRegistry.n8n.backup.requiredFiles == [".n8n/config"];
    suppliedKeyStillHasNativeState = secretKey.nixstead.serviceRegistry.n8n.backup.requiredFiles == [".n8n/config" ".n8n/database.sqlite"];
    suppliedKeyUsesSystemdCredential =
      lib.elem "n8n_encryption_key_file:/run/secrets/n8n-key" secretKey.systemd.services.n8n.serviceConfig.LoadCredential
      && secretKey.systemd.services.n8n.environment.N8N_ENCRYPTION_KEY_FILE == "%d/n8n_encryption_key_file";
  }
