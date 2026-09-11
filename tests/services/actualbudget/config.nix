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
        nixstead.services.productivity.actualbudget = {
          enable = true;
          inherit port;
          domain = "fixture-actualbudget.example.test";
        };
      }
    ]).config;
  profile = serverFiles:
    (mkSystem [
      {
        nixstead.services.productivity.actualbudget.enable = true;
        services.actual = {
          user = "budget-owner";
          group = "budget-state";
          settings = {
            dataDir = lib.mkForce "/srv/budget";
            inherit serverFiles;
            userFiles = "/srv/budget-files";
          };
        };
        users.users.budget-owner = {
          isSystemUser = true;
          group = "budget-state";
        };
        users.groups.budget-state = {};
      }
    ]).config;
  custom = profile "/srv/account-state";
  nested = profile "/srv/budget/account-state";
in
  serviceContract {
    id = "actualbudget";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.services.actual.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.actualbudget.port = 70000;}]).config.nixstead.services.productivity.actualbudget.port).success;

    nativeListener = cfg.services.actual.settings.port == port && cfg.services.actual.settings.hostname == "127.0.0.1";
    nativeDataPath = cfg.services.actual.settings.dataDir == "/var/lib/actual";
    backupUsesNativeData = cfg.nixstead.serviceRegistry.actualbudget.backup.paths == ["/var/lib/actual"];
    defaultDynamicOwner = cfg.services.actual.user == null && cfg.services.actual.group == null && cfg.systemd.services.actual.serviceConfig.DynamicUser && cfg.nixstead.serviceRegistry.actualbudget.backup.owner == "root" && cfg.nixstead.serviceRegistry.actualbudget.backup.group == "root";
    defaultRecoveryInputs = cfg.nixstead.serviceRegistry.actualbudget.backup.requiredFiles == [".migrate" "server-files/account.sqlite"] && cfg.nixstead.serviceRegistry.actualbudget.backup.requiredJsonFiles == [".migrate"];
    nativeSeparateRoots = custom.nixstead.serviceRegistry.actualbudget.backup.paths == ["/srv/budget" "/srv/account-state" "/srv/budget-files"];
    nativeNamedOwnership = custom.nixstead.serviceRegistry.actualbudget.backup.owner == "budget-owner" && custom.nixstead.serviceRegistry.actualbudget.backup.group == "budget-state" && !custom.systemd.services.actual.serviceConfig.DynamicUser;
    allNativeMounts = custom.systemd.services.actual.unitConfig.RequiresMountsFor == ["/srv/budget" "/srv/account-state" "/srv/budget-files"];
    outsideAccountRequirementOmitted = custom.nixstead.serviceRegistry.actualbudget.backup.requiredFiles == [".migrate"];
    nativeNestedAccountRequirement = nested.nixstead.serviceRegistry.actualbudget.backup.paths == ["/srv/budget" "/srv/budget-files"] && nested.nixstead.serviceRegistry.actualbudget.backup.requiredFiles == [".migrate" "account-state/account.sqlite"];
    mountRequired = lib.elem "/var/lib/actual" cfg.systemd.services.actual.unitConfig.RequiresMountsFor;
    fixedPathRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.actualbudget.paths.dataDir = "/srv/budget";}]).config.nixstead.services.productivity.actualbudget.paths.dataDir).success;
  }
