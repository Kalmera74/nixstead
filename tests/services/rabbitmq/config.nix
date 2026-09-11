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
        nixstead.services.dev.rabbitmq = {
          enable = true;
          inherit port;
          domain = "fixture-rabbitmq.example.test";
        };
      }
    ]).config;
in
  serviceContract {
    id = "rabbitmq";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.rabbitmq.enable;
  }
  // {
    backupIncludesNodeState = cfg.nixstead.serviceRegistry.rabbitmq.backup.paths == [cfg.services.rabbitmq.dataDir];
    backupStopsBroker = cfg.nixstead.serviceRegistry.rabbitmq.backup.units == ["rabbitmq.service"];
    backupRequiresNodeIdentity = cfg.nixstead.serviceRegistry.rabbitmq.backup.requiredFiles == [".erlang.cookie"];
    mountRequired = lib.elem cfg.services.rabbitmq.dataDir cfg.systemd.services.rabbitmq.unitConfig.RequiresMountsFor;
    customStateCovered =
      (mkSystem [
        {
          nixstead.services.dev.rabbitmq.enable = true;
          services.rabbitmq.dataDir = "/srv/broker";
        }
      ]).config.nixstead.serviceRegistry.rabbitmq.backup.paths
      == ["/srv/broker"];
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.rabbitmq.port = 70000;}]).config.nixstead.services.dev.rabbitmq.port).success;

    nativeListener = cfg.services.rabbitmq.port == port && cfg.services.rabbitmq.listenAddress == "127.0.0.1";
    runtimeCredentials = lib.elem "/run/secrets/rendered/rabbitmq-admin.env" cfg.systemd.services.rabbitmq.serviceConfig.EnvironmentFile;
    credentialsOwnedByBroker = cfg.sops.templates."rabbitmq-admin.env".owner == "rabbitmq";
    passwordIsPlaceholder = lib.hasInfix cfg.sops.placeholder."devdb/rabbitmq/rootPassword" cfg.sops.templates."rabbitmq-admin.env".content;
    bootstrapRotatesAccount = lib.hasInfix "change_password" cfg.systemd.services.rabbitmq.postStart;
    bootstrapPasswordUsesStdin = lib.hasInfix "printf '%s\\n' \"$rabbitmq_root_password\" |" cfg.systemd.services.rabbitmq.postStart && !lib.hasInfix "change_password \"$rabbitmq_root_user\" \"$rabbitmq_root_password\"" cfg.systemd.services.rabbitmq.postStart;
    bootstrapRemovesGuest = lib.hasInfix "delete_user guest" cfg.systemd.services.rabbitmq.postStart;
  }
