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
        nixstead.services.dev.gitea = {
          enable = true;
          inherit port;
          domain = "fixture-gitea.example.test";
          paths.stateDir = "/srv/gitea";
        };
      }
    ]).config;
  native = database:
    (mkSystem [
      {
        nixstead.services.dev.gitea.enable = true;
        services.gitea = {
          stateDir = "/srv/native-gitea";
          repositoryRoot = "/srv/native-repositories";
          inherit database;
        };
      }
    ]).config.nixstead.serviceRegistry.gitea.backup;
  customIdentity =
    (mkSystem [
      {
        nixstead.services.dev.gitea.enable = true;
        services.gitea = {
          user = "forge-owner";
          group = "forge-group";
        };
        users.users.forge-owner = {
          isSystemUser = true;
          group = "forge-group";
        };
        users.groups.forge-group = {};
      }
    ]).config;
in
  serviceContract {
    id = "gitea";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.gitea.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.gitea.port = 70000;}]).config.nixstead.services.dev.gitea.port).success;

    nativeListener = cfg.services.gitea.settings.server.HTTP_PORT == port && cfg.services.gitea.settings.server.HTTP_ADDR == "127.0.0.1";
    nativeStatePath = cfg.services.gitea.stateDir == "/srv/gitea";
    backupUsesStatePath = cfg.nixstead.serviceRegistry.gitea.backup.paths == ["/srv/gitea"];
    runtimeCredentials = lib.elem "/run/secrets/rendered/gitea-initial-admin.env" cfg.systemd.services.gitea.serviceConfig.EnvironmentFile;
    registrationDisabled = cfg.services.gitea.settings.service.DISABLE_REGISTRATION;
    customRestoreIdentity = customIdentity.nixstead.serviceRegistry.gitea.backup.owner == "forge-owner" && customIdentity.nixstead.serviceRegistry.gitea.backup.group == "forge-group";
    customCredentialOwner = customIdentity.sops.templates."gitea-initial-admin.env".owner == "forge-owner";
    customIdentityMediaGroup = lib.elem customIdentity.nixstead.host.groups.media customIdentity.users.users.forge-owner.extraGroups;
    primaryDatabaseRequired = cfg.nixstead.serviceRegistry.gitea.backup.requiredFiles == ["data/gitea.db"];
    nativePathOverridesPreserved = (native {}).paths == ["/srv/native-gitea" "/srv/native-repositories"];
    customNativeSQLiteRequired = (native {path = "/srv/native-gitea/custom/database.sqlite";}).requiredFiles == ["custom/database.sqlite"];
    externalSQLiteNotMisrepresented = (native {path = "/srv/external-gitea.sqlite";}).requiredFiles == [];
    externalEnginesOmitSQLiteRequirement = lib.all (type: (native {inherit type;}).requiredFiles == []) ["postgres" "mysql"];
    customBootstrapConfig = lib.hasInfix "/srv/gitea/custom/conf/app.ini" cfg.systemd.services.gitea.postStart;
  }
