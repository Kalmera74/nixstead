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
        nixstead.services.dev.mongodb = {
          enable = true;
          inherit port;
          domain = "fixture-mongodb.example.test";
        };
        services.mongodb.initialScript = ./initial-script.js;
      }
    ]).config;
  custom =
    (mkSystem [
      {
        nixstead.services.dev.mongodb.enable = true;
        services.mongodb.dbpath = "/srv/mongodb";
      }
    ]).config;
in
  serviceContract {
    id = "mongodb";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.mongodb.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.mongodb.port = 70000;}]).config.nixstead.services.dev.mongodb.port).success;

    nativeListener = cfg.services.mongodb.bind_ip == "127.0.0.1" && lib.hasInfix "net.port: ${toString port}" cfg.services.mongodb.extraConfig;
    authenticationEnabled = cfg.services.mongodb.enableAuth;
    rootPasswordFile = cfg.services.mongodb.initialRootPasswordFile == "/run/secrets/devdb/mongodb/rootPassword";
    rootPasswordOwnedByMongo = cfg.sops.secrets."devdb/mongodb/rootPassword".owner == "mongodb";
    bootstrapUsesCustomPort = lib.hasInfix "--host 127.0.0.1 --port ${toString port}" cfg.systemd.services.mongodb.preStart;
    bootstrapKeepsAuthenticationEnabled = lib.hasInfix "/bin/mongod --auth --config" cfg.systemd.services.mongodb.preStart;
    initialScriptUsesCustomPort = lib.hasInfix "--host 127.0.0.1 --port ${toString port} admin --file" cfg.systemd.services.mongodb.postStart;
    bootstrapDoesNotInterpolatePassword = !(lib.hasInfix "initialRootPassword=" cfg.systemd.services.mongodb.preStart) && lib.hasInfix "--file" cfg.systemd.services.mongodb.preStart;
    initialScriptHasNoPasswordArgument = !(lib.hasInfix "-p " cfg.systemd.services.mongodb.postStart) && !(lib.hasInfix "initialRootPassword=" cfg.systemd.services.mongodb.postStart);
    bootstrapHasBoundedCleanup = lib.hasInfix "trap cleanup EXIT" cfg.systemd.services.mongodb.preStart && lib.hasInfix "SECONDS + 60" cfg.systemd.services.mongodb.preStart;
    missingInitialSecretGuard = lib.hasInfix "Missing or empty initial MongoDB password file" cfg.systemd.services.mongodb.preStart;
    customDatabasePath = custom.services.mongodb.dbpath == "/srv/mongodb";
    backupUsesNativeData = custom.nixstead.serviceRegistry.mongodb.backup.paths == ["/srv/mongodb"];
    backupRequiresWiredTigerMetadata = custom.nixstead.serviceRegistry.mongodb.backup.requiredFiles == ["storage.bson" "WiredTiger" "WiredTiger.wt" "WiredTiger.turtle"];
    backupChecksWithNativePackage = custom.nixstead.serviceRegistry.mongodb.backup.mongodbDirectoryCheck.executable == "${custom.services.mongodb.package}/bin/mongod";
    backupCheckerHasFixedArguments = custom.nixstead.serviceRegistry.mongodb.backup.mongodbDirectoryCheck.arguments == ["--auth" "--bind_ip" "127.0.0.1" "--port" "27017" "--nounixsocket" "--wiredTigerCacheSizeGB" "0.25"];
  }
