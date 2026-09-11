{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr.readarr = {
      enable = true;
      port = 28104;
    };
    nixstead.services.arr.credentials.enable = true;
  };
  config = (mkSystem [selected]).config;
  custom = (mkSystem [selected {services.readarr.dataDir = "/var/lib/readarr-custom";}]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.readarr = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "readarr";
    group = "arr";
    port = 28104;
    nativeEnabled = c: c.services.readarr.enable;
  })
  // {
    nativeStatePath = custom.services.readarr.dataDir == "/var/lib/readarr-custom";
    backupDefaultState = config.nixstead.serviceRegistry.readarr.backup.paths == [config.services.readarr.dataDir];
    backupFollowsNativePath = custom.nixstead.serviceRegistry.readarr.backup.paths == ["/var/lib/readarr-custom"];
    backupQuiescesNativeUnit = config.nixstead.serviceRegistry.readarr.backup.units == ["readarr.service"];
    nativePort = config.services.readarr.settings.server.port == 28104;
    nativeLoopback = config.services.readarr.settings.server.bindaddress == "127.0.0.1";
    publicListener = public.services.readarr.settings.server.bindaddress == "0.0.0.0";
    noUnsupportedSharedCredentialPublisher = !(config.systemd.services ? nixstead-credential-readarr);
    sharedMediaGroup = lib.elem config.nixstead.host.groups.media config.users.users.readarr.extraGroups;
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.readarr.port = 70000;}]).config.nixstead.services.arr.readarr.port).success;
  }
