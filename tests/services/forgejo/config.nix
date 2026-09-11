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
        nixstead.services.dev.forgejo = {
          enable = true;
          inherit port;
          domain = "fixture-forgejo.example.test";
          paths = {
            stateDir = "/srv/forgejo-state";
            repositoryDir = "/srv/repositories";
          };
        };
      }
    ]).config;
  native = database:
    (mkSystem [
      {
        nixstead.services.dev.forgejo.enable = true;
        services.forgejo = {
          stateDir = "/srv/native-forgejo";
          repositoryRoot = "/srv/native-repositories";
          inherit database;
        };
      }
    ]).config.nixstead.serviceRegistry.forgejo.backup;
  customIdentity =
    (mkSystem [
      {
        nixstead.services.dev.forgejo.enable = true;
        services.forgejo = {
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
    id = "forgejo";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.forgejo.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.forgejo.port = 70000;}]).config.nixstead.services.dev.forgejo.port).success;

    nativeListener = cfg.services.forgejo.settings.server.HTTP_PORT == port && cfg.services.forgejo.settings.server.HTTP_ADDR == "127.0.0.1";
    nativeStatePath = cfg.services.forgejo.stateDir == "/srv/forgejo-state";
    repositoryPath = cfg.services.forgejo.repositoryRoot == "/srv/repositories";
    backupIncludesRepositories = cfg.nixstead.serviceRegistry.forgejo.backup.paths == ["/srv/forgejo-state" "/srv/repositories"];
    mountDependencies = lib.all (path: lib.elem path cfg.systemd.services.forgejo.unitConfig.RequiresMountsFor) ["/srv/forgejo-state" "/srv/repositories"];
    runtimeCredentials = lib.elem "/run/secrets/rendered/forgejo-initial-admin.env" cfg.systemd.services.forgejo.serviceConfig.EnvironmentFile;
    registrationDisabled = cfg.services.forgejo.settings.service.DISABLE_REGISTRATION;
    customRestoreIdentity = customIdentity.nixstead.serviceRegistry.forgejo.backup.owner == "forge-owner" && customIdentity.nixstead.serviceRegistry.forgejo.backup.group == "forge-group";
    customCredentialOwner = customIdentity.sops.templates."forgejo-initial-admin.env".owner == "forge-owner";
    customIdentityMediaGroup = lib.elem customIdentity.nixstead.host.groups.media customIdentity.users.users.forge-owner.extraGroups;
    primaryDatabaseRequired = cfg.nixstead.serviceRegistry.forgejo.backup.requiredFiles == ["data/forgejo.db"];
    nativePathOverridesPreserved = (native {}).paths == ["/srv/native-forgejo" "/srv/native-repositories"];
    customNativeSQLiteRequired = (native {path = "/srv/native-forgejo/custom/database.sqlite";}).requiredFiles == ["custom/database.sqlite"];
    externalSQLiteNotMisrepresented = (native {path = "/srv/external-forgejo.sqlite";}).requiredFiles == [];
    externalEnginesOmitSQLiteRequirement = lib.all (type: (native {inherit type;}).requiredFiles == []) ["postgres" "mysql"];
    customBootstrapConfig = lib.hasInfix "/srv/forgejo-state/custom/conf/app.ini" cfg.systemd.services.forgejo.postStart;
  }
