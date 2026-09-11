{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr.prowlarr = {
      enable = true;
      port = 28106;
    };
    nixstead.services.arr.credentials.enable = true;
  };
  config = (mkSystem [selected]).config;
  custom = (mkSystem [selected {services.prowlarr.dataDir = "/var/lib/prowlarr-custom";}]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.prowlarr = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "prowlarr";
    group = "arr";
    port = 28106;
    nativeEnabled = c: c.services.prowlarr.enable;
  })
  // {
    nativeStatePath = custom.services.prowlarr.dataDir == "/var/lib/prowlarr-custom";
    backupDefaultState = config.nixstead.serviceRegistry.prowlarr.backup.paths == [config.services.prowlarr.dataDir];
    backupFollowsNativePath = custom.nixstead.serviceRegistry.prowlarr.backup.paths == ["/var/lib/prowlarr-custom"];
    backupQuiescesNativeUnit = config.nixstead.serviceRegistry.prowlarr.backup.units == ["prowlarr.service"];
    nativePort = config.services.prowlarr.settings.server.port == 28106;
    nativeLoopback = config.services.prowlarr.settings.server.bindaddress == "127.0.0.1";
    publicListener = public.services.prowlarr.settings.server.bindaddress == "0.0.0.0";
    credentialFollowsNativeState = custom.nixstead.serviceRegistry.prowlarr.api.stateFile == "/var/lib/prowlarr-custom/config.xml";
    runtimeCredentialEnvironment = lib.elem "/run/nixstead-credentials/prowlarr/native.env" config.systemd.services.prowlarr.serviceConfig.EnvironmentFile;
    storeCredentialRejected = rejects "Managed API key overrides" {nixstead.services.arr.credentials.apiKeyFiles.prowlarr = "/nix/store/forbidden-api-key";};
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.prowlarr.port = 70000;}]).config.nixstead.services.arr.prowlarr.port).success;
  }
