{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr.sonarr = {
      enable = true;
      port = 28101;
    };
    nixstead.services.arr.credentials.enable = true;
  };
  config = (mkSystem [selected]).config;
  custom = (mkSystem [selected {services.sonarr.dataDir = "/var/lib/sonarr-custom";}]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.sonarr = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "sonarr";
    group = "arr";
    port = 28101;
    nativeEnabled = c: c.services.sonarr.enable;
  })
  // {
    nativeStatePath = custom.services.sonarr.dataDir == "/var/lib/sonarr-custom";
    backupDefaultState = config.nixstead.serviceRegistry.sonarr.backup.paths == ["/var/lib/sonarr"];
    backupQuiescesNativeUnit = config.nixstead.serviceRegistry.sonarr.backup.units == ["sonarr.service"];
    nativePort = config.services.sonarr.settings.server.port == 28101;
    nativeLoopback = config.services.sonarr.settings.server.bindaddress == "127.0.0.1";
    publicListener = public.services.sonarr.settings.server.bindaddress == "0.0.0.0";
    credentialFollowsNativeState = custom.nixstead.serviceRegistry.sonarr.api.stateFile == "/var/lib/sonarr-custom/config.xml";
    runtimeCredentialEnvironment = lib.elem "/run/nixstead-credentials/sonarr/native.env" config.systemd.services.sonarr.serviceConfig.EnvironmentFile;
    storeCredentialRejected = rejects "Managed API key overrides" {nixstead.services.arr.credentials.apiKeyFiles.sonarr = "/nix/store/forbidden-api-key";};
    sharedMediaGroup = lib.elem config.nixstead.host.groups.media config.users.users.sonarr.extraGroups;
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.sonarr.port = 70000;}]).config.nixstead.services.arr.sonarr.port).success;
  }
