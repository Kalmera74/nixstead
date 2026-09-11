{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.kavita = {
      enable = true;
      port = 28205;
    };
    nixstead.services.media.kavita.paths.dataDir = "/var/lib/kavita-custom";
  };
  config = (mkSystem [selected]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.kavita = "public";}]).config;
  native =
    (mkSystem [
      selected
      {
        services.kavita = {
          dataDir = lib.mkForce "/srv/native-kavita";
          user = "reader-owner";
          tokenKeyFile = lib.mkForce "/run/reader-signing-key";
        };
      }
    ]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "kavita";
    group = "media";
    port = 28205;
    nativeEnabled = c: c.services.kavita.enable;
  })
  // {
    nativePort = config.services.kavita.settings.Port == 28205;
    nativeLoopback = config.services.kavita.settings.IpAddresses == "127.0.0.1";
    publicListener = public.services.kavita.settings.IpAddresses == "0.0.0.0";
    nativeState = config.services.kavita.dataDir == "/var/lib/kavita-custom";
    runtimeSigningKey = config.services.kavita.tokenKeyFile == "/var/lib/kavita-custom/kavita-token-key";
    keyBeforeApplication = lib.elem "kavita-token-key.service" config.systemd.services.kavita.requires && lib.elem "kavita-token-key.service" config.systemd.services.kavita.after;
    mountDependencies = lib.elem "/var/lib/kavita-custom" config.systemd.services.kavita.unitConfig.RequiresMountsFor;
    backupIncludesDefaultSigningKey = config.nixstead.serviceRegistry.kavita.backup.paths == ["/var/lib/kavita-custom"];
    nativeBackupRoot = native.nixstead.serviceRegistry.kavita.backup.paths == ["/srv/native-kavita"];
    nativeRestoreAccount = native.nixstead.serviceRegistry.kavita.backup.owner == "reader-owner" && native.nixstead.serviceRegistry.kavita.backup.group == "reader-owner";
    nativeKeyGenerationDirectory = native.systemd.services.kavita-token-key.unitConfig.RequiresMountsFor == ["/run"];
    nativeMountOrdering = native.systemd.services.kavita.unitConfig.RequiresMountsFor == ["/run" "/srv/native-kavita"];

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.kavita.port = 70000;}]).config.nixstead.services.media.kavita.port).success;
  }
