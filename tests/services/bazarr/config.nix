{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr.bazarr = {
      enable = true;
      port = 28105;
    };
    nixstead.services.arr.credentials.enable = true;
  };
  config = (mkSystem [selected]).config;
  custom = (mkSystem [selected {services.bazarr.dataDir = "/var/lib/bazarr-custom";}]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.bazarr = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "bazarr";
    group = "arr";
    port = 28105;
    nativeEnabled = c: c.services.bazarr.enable;
  })
  // {
    nativeStatePath = custom.services.bazarr.dataDir == "/var/lib/bazarr-custom";
    backupDefaultState = config.nixstead.serviceRegistry.bazarr.backup.paths == [config.services.bazarr.dataDir];
    backupFollowsNativePath = custom.nixstead.serviceRegistry.bazarr.backup.paths == ["/var/lib/bazarr-custom"];
    backupQuiescesNativeUnit = config.nixstead.serviceRegistry.bazarr.backup.units == ["bazarr.service"];
    nativePort = config.services.bazarr.listenPort == 28105;
    nativeLoopback = config.systemd.services.bazarr.environment.DYNACONF_GENERAL__IP == "127.0.0.1";
    publicListener = public.systemd.services.bazarr.environment.DYNACONF_GENERAL__IP == "0.0.0.0";
    credentialFollowsNativeState = custom.nixstead.serviceRegistry.bazarr.api.stateFile == "/var/lib/bazarr-custom/config/config.yaml";
    runtimeCredentialEnvironment = lib.elem "/run/nixstead-credentials/bazarr/native.env" config.systemd.services.bazarr.serviceConfig.EnvironmentFile;
    storeCredentialRejected = rejects "Managed API key overrides" {nixstead.services.arr.credentials.apiKeyFiles.bazarr = "/nix/store/forbidden-api-key";};
    sharedMediaGroup = lib.elem config.nixstead.host.groups.media config.users.users.bazarr.extraGroups;
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.bazarr.port = 70000;}]).config.nixstead.services.arr.bazarr.port).success;
  }
