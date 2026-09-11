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
        nixstead.services.dev.redis = {
          enable = true;
          inherit port;
          domain = "fixture-redis.example.test";
        };
        services.redis.servers."".settings = {
          dir = lib.mkForce "/srv/redis";
          dbfilename = lib.mkForce "suite.rdb";
        };
      }
    ]).config;
  effectiveBackup = overrides:
    (mkSystem [
      {nixstead.services.dev.redis.enable = true;}
      {services.redis.servers."" = overrides;}
    ]).config.nixstead.serviceRegistry.redis.backup;
in
  serviceContract {
    id = "redis";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.redis.servers ? "" && c.services.redis.servers."".enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.redis.port = 70000;}]).config.nixstead.services.dev.redis.port).success;

    nativeListener = cfg.services.redis.servers."".port == port && cfg.services.redis.servers."".bind == "127.0.0.1";
    runtimeAcl = cfg.services.redis.servers."".settings.aclfile == "/run/secrets/rendered/redis-users.acl";
    defaultUserDisabled = lib.hasInfix "user default off" cfg.sops.templates."redis-users.acl".content;
    runtimePasswordPlaceholder = lib.hasInfix cfg.sops.placeholder."devdb/redis/rootPassword" cfg.sops.templates."redis-users.acl".content;
    credentialOwnership = cfg.sops.templates."redis-users.acl".owner == "redis";
    credentialRotation = cfg.sops.templates."redis-users.acl".restartUnits == ["redis.service"];
    nativeRdbSchedule = cfg.services.redis.servers."".save != [] && !cfg.services.redis.servers."".appendOnly;
    customBackupPath = cfg.nixstead.serviceRegistry.redis.backup.paths == ["/srv/redis"];
    customStateIsWritable = lib.elem "/srv/redis" cfg.systemd.services.redis.serviceConfig.ReadWritePaths;
    customMountRequired = lib.elem "/srv/redis" cfg.systemd.services.redis.unitConfig.RequiresMountsFor;
    stoppedWriterBackup = cfg.nixstead.serviceRegistry.redis.backup.units == ["redis.service"];
    renderedCacheOverrideOmitsRdbValidation =
      (effectiveBackup {
        settings.save = lib.mkForce ''""'';
      }).rdb
      == null;
    renderedAofOverrideOmitsRdbValidation =
      (effectiveBackup {
        settings.appendOnly = lib.mkForce true;
      }).rdb
      == null;
    renderedRdbOverrideRequiresValidation =
      (effectiveBackup {
        save = [];
        settings.save = lib.mkForce ["60 1"];
      }).rdb
      != null;
    nativeSnapshotValidation =
      cfg.nixstead.serviceRegistry.redis.backup.rdb
      == {
        file = "suite.rdb";
        checker = "${cfg.services.redis.package}/bin/redis-check-rdb";
      };
  }
