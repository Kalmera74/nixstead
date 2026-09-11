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
        nixstead.services.dev.ntfy = {
          enable = true;
          inherit port;
          domain = "fixture-ntfy.example.test";
          adminUsername = "fixture-admin";
          adminPasswordFile = "/run/credentials/ntfy-admin";
        };
      }
    ]).config;
  generated = (mkSystem [{nixstead.services.dev.ntfy.enable = true;}]).config;
in
  serviceContract {
    id = "ntfy";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.ntfy-sh.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.ntfy.port = 70000;}]).config.nixstead.services.dev.ntfy.port).success;

    nativeListener = cfg.services.ntfy-sh.settings."listen-http" == "127.0.0.1:${toString port}";
    anonymousDenied = cfg.services.ntfy-sh.settings."auth-default-access" == "deny-all";
    authenticationDatabase = cfg.services.ntfy-sh.settings."auth-file" == "/var/lib/ntfy-sh/user.db";
    attachmentDirectory = cfg.services.ntfy-sh.settings."attachment-cache-dir" == "/var/lib/ntfy-sh/attachments";
    generatedEnvironmentFile = cfg.services.ntfy-sh.environmentFile == "/var/lib/ntfy-sh/auth.env";
    credentialOverride = lib.elem "/run/credentials/ntfy-admin" cfg.systemd.services.ntfy-sh.unitConfig.RequiresMountsFor;
    backupIncludesOwnedState = cfg.nixstead.serviceRegistry.ntfy.backup.paths == ["/var/lib/ntfy-sh"];
    backupHandlesNativeDynamicUser = cfg.nixstead.serviceRegistry.ntfy.backup.dynamicUser;
    generatedPasswordRequiredForRestore = generated.nixstead.serviceRegistry.ntfy.backup.requiredFiles == ["user.db" "cache.db" "admin-password"];
    externalPasswordRemainsExternal = cfg.nixstead.serviceRegistry.ntfy.backup.requiredFiles == ["user.db" "cache.db"];
    bootstrapSharesPrivateState =
      cfg.systemd.services.ntfy-bootstrap-credentials.serviceConfig.DynamicUser
      && cfg.systemd.services.ntfy-bootstrap-credentials.serviceConfig.StateDirectory == "ntfy-sh"
      && cfg.systemd.services.ntfy-bootstrap-credentials.serviceConfig.User == cfg.services.ntfy-sh.user;
    externalPasswordUsesSystemdCredential = cfg.systemd.services.ntfy-bootstrap-credentials.serviceConfig.LoadCredential == ["admin-password:/run/credentials/ntfy-admin"];
    generatedPasswordNeedsNoExternalCredential = generated.systemd.services.ntfy-bootstrap-credentials.serviceConfig.LoadCredential == [];
    fixedPathRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.ntfy.paths.dataDir = "/srv/ntfy";}]).config.nixstead.services.dev.ntfy.paths.dataDir).success;
  }
