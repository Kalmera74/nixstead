{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr.lidarr = {
      enable = true;
      port = 28103;
    };
    nixstead.services.arr.credentials.enable = true;
  };
  config = (mkSystem [selected]).config;
  custom = (mkSystem [selected {services.lidarr.dataDir = "/var/lib/lidarr-custom";}]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.lidarr = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "lidarr";
    group = "arr";
    port = 28103;
    nativeEnabled = c: c.services.lidarr.enable;
  })
  // {
    nativeStatePath = custom.services.lidarr.dataDir == "/var/lib/lidarr-custom";
    backupDefaultState = config.nixstead.serviceRegistry.lidarr.backup.paths == ["/var/lib/lidarr"];
    backupQuiescesNativeUnit = config.nixstead.serviceRegistry.lidarr.backup.units == ["lidarr.service"];
    nativePort = config.services.lidarr.settings.server.port == 28103;
    nativeLoopback = config.services.lidarr.settings.server.bindaddress == "127.0.0.1";
    publicListener = public.services.lidarr.settings.server.bindaddress == "0.0.0.0";
    credentialFollowsNativeState = custom.nixstead.serviceRegistry.lidarr.api.stateFile == "/var/lib/lidarr-custom/config.xml";
    runtimeCredentialEnvironment = lib.elem "/run/nixstead-credentials/lidarr/native.env" config.systemd.services.lidarr.serviceConfig.EnvironmentFile;
    storeCredentialRejected = rejects "Managed API key overrides" {nixstead.services.arr.credentials.apiKeyFiles.lidarr = "/nix/store/forbidden-api-key";};
    sharedMediaGroup = lib.elem config.nixstead.host.groups.media config.users.users.lidarr.extraGroups;
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.lidarr.port = 70000;}]).config.nixstead.services.arr.lidarr.port).success;
  }
