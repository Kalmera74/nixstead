{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.komga = {
      enable = true;
      port = 28204;
    };
  };
  config = (mkSystem [selected]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.komga = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "komga";
    group = "media";
    port = 28204;
    nativeEnabled = c: c.services.komga.enable;
  })
  // {
    nativePort = config.services.komga.settings.server.port == 28204;
    nativeLoopback = config.services.komga.settings.server.address == "127.0.0.1";
    publicListener = public.services.komga.settings.server.address == "0.0.0.0";
    backupState =
      config.nixstead.serviceRegistry.komga.backup.paths
      == ["/var/lib/komga"]
      && config.nixstead.serviceRegistry.komga.backup.units == ["komga.service"]
      && config.nixstead.serviceRegistry.komga.backup.requiredFiles == ["database.sqlite"]
      && config.nixstead.serviceRegistry.komga.backup.requiredSQLiteFiles == ["database.sqlite"];
    nativeState = config.services.komga.stateDir == "/var/lib/komga";

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.komga.port = 70000;}]).config.nixstead.services.media.komga.port).success;
  }
