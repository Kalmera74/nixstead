{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.kiwix = {
      enable = true;
      port = 28207;
    };
    nixstead.services.media.kiwix.paths.dataDir = "/srv/zim";
  };
  config = (mkSystem [selected]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.kiwix = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "kiwix";
    group = "media";
    port = 28207;
    nativeEnabled = c: c.systemd.services ? kiwix-serve;
  })
  // {
    nativePort = lib.hasInfix "--port 28207" config.systemd.services.kiwix-serve.serviceConfig.ExecStart;
    nativeLoopback = lib.hasInfix "--address 127.0.0.1" config.systemd.services.kiwix-serve.serviceConfig.ExecStart;
    publicListener = lib.hasInfix "--address 0.0.0.0" public.systemd.services.kiwix-serve.serviceConfig.ExecStart;
    nativeLibraryPath = lib.hasInfix "--library /srv/zim/library.xml" config.systemd.services.kiwix-serve.serviceConfig.ExecStart;
    nativeLibraryReload = lib.hasInfix "--monitorLibrary" config.systemd.services.kiwix-serve.serviceConfig.ExecStart;
    refreshMountDependency = config.systemd.services.kiwix-library-refresh.unitConfig.RequiresMountsFor == ["/srv/zim"];
    refreshBeforeServe = lib.elem "kiwix-library-refresh.service" config.systemd.services.kiwix-serve.requires && lib.elem "kiwix-library-refresh.service" config.systemd.services.kiwix-serve.after;
    noImplicitSourceBackup = config.nixstead.serviceRegistry.kiwix.backup == null;

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.kiwix.port = 70000;}]).config.nixstead.services.media.kiwix.port).success;
  }
