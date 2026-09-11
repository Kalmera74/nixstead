{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr.radarr = {
      enable = true;
      port = 28102;
    };
    nixstead.services.arr.credentials.enable = true;
  };
  config = (mkSystem [selected]).config;
  custom = (mkSystem [selected {services.radarr.dataDir = "/var/lib/radarr-custom";}]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.radarr = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "radarr";
    group = "arr";
    port = 28102;
    nativeEnabled = c: c.services.radarr.enable;
  })
  // {
    nativeStatePath = custom.services.radarr.dataDir == "/var/lib/radarr-custom";
    backupDefaultState = config.nixstead.serviceRegistry.radarr.backup.paths == ["/var/lib/radarr"];
    backupQuiescesNativeUnit = config.nixstead.serviceRegistry.radarr.backup.units == ["radarr.service"];
    nativePort = config.services.radarr.settings.server.port == 28102;
    nativeLoopback = config.services.radarr.settings.server.bindaddress == "127.0.0.1";
    publicListener = public.services.radarr.settings.server.bindaddress == "0.0.0.0";
    credentialFollowsNativeState = custom.nixstead.serviceRegistry.radarr.api.stateFile == "/var/lib/radarr-custom/config.xml";
    runtimeCredentialEnvironment = lib.elem "/run/nixstead-credentials/radarr/native.env" config.systemd.services.radarr.serviceConfig.EnvironmentFile;
    storeCredentialRejected = rejects "Managed API key overrides" {nixstead.services.arr.credentials.apiKeyFiles.radarr = "/nix/store/forbidden-api-key";};
    sharedMediaGroup = lib.elem config.nixstead.host.groups.media config.users.users.radarr.extraGroups;
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.radarr.port = 70000;}]).config.nixstead.services.arr.radarr.port).success;
  }
