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
        nixstead.services.productivity.mealie = {
          enable = true;
          inherit port;
          domain = "fixture-mealie.example.test";
        };
      }
    ]).config;
in
  serviceContract {
    id = "mealie";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.services.mealie.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.mealie.port = 70000;}]).config.nixstead.services.productivity.mealie.port).success;

    nativeListener = cfg.services.mealie.port == port && cfg.services.mealie.listenAddress == "127.0.0.1";
    registrationDisabled = cfg.services.mealie.settings.ALLOW_SIGNUP == "false";
    customBaseUrl = cfg.services.mealie.settings.BASE_URL == "https://fixture-mealie.example.test";
    backupUsesFixedData = cfg.nixstead.serviceRegistry.mealie.backup.paths == ["/var/lib/mealie"];
    nativeDataRoot = cfg.systemd.services.mealie.environment.DATA_DIR == "/var/lib/mealie";
    unownedNativePathRejected =
      lib.any (item: !item.assertion && lib.hasInfix "Mealie recovery requires" item.message)
      (mkSystem [
        {
          nixstead.services.productivity.mealie.enable = true;
          services.mealie.settings.DATA_DIR = "/srv/mealie";
        }
      ]).config.assertions;
    dynamicIdentityRestoration = cfg.nixstead.serviceRegistry.mealie.backup.dynamicUser && cfg.systemd.services.mealie.serviceConfig.DynamicUser;
    requiredDatabaseAndKeys = cfg.nixstead.serviceRegistry.mealie.backup.requiredFiles == ["mealie.db" ".secret" ".session_secret"];
    mountRequired = lib.elem "/var/lib/mealie" cfg.systemd.services.mealie.unitConfig.RequiresMountsFor;
    fixedPathRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.mealie.paths.dataDir = "/srv/mealie";}]).config.nixstead.services.productivity.mealie.paths.dataDir).success;
  }
