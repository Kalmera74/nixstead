{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.jellyfin = {
      enable = true;
      port = 28201;
    };
  };
  config = (mkSystem [selected]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.jellyfin = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
  custom = (mkSystem [selected {services.jellyfin.configDir = "/var/lib/jellyfin-custom/config";}]).config;
in
  (serviceContract {
    id = "jellyfin";
    group = "media";
    port = 28201;
    nativeEnabled = c: c.services.jellyfin.enable;
  })
  // {
    nativePortScript = lib.hasInfix "28201" config.systemd.services.jellyfin.preStart;
    nativeLoopbackScript = lib.hasInfix "127.0.0.1" config.systemd.services.jellyfin.preStart;
    publicListenerScript = lib.hasInfix "0.0.0.0" public.systemd.services.jellyfin.preStart;
    mediaIdentity = lib.all (group: lib.elem group config.users.users.jellyfin.extraGroups) ["video" "render" config.nixstead.host.groups.media];
    backupState = config.nixstead.serviceRegistry.jellyfin.backup.paths == ["/var/lib/jellyfin"] && config.nixstead.serviceRegistry.jellyfin.backup.units == ["jellyfin.service"];
    customNativeConfigPath = lib.hasInfix "/var/lib/jellyfin-custom/config/network.xml" custom.systemd.services.jellyfin.preStart;
    separateNativeConfigBackedUp = custom.nixstead.serviceRegistry.jellyfin.backup.paths == ["/var/lib/jellyfin" "/var/lib/jellyfin-custom/config"];
    defaultCacheRecreatedOnStart = config.systemd.services.jellyfin.serviceConfig.CacheDirectory == "jellyfin" && config.systemd.services.jellyfin.serviceConfig.CacheDirectoryMode == "0700";
    customNativeCachePreserved = let
      changed = (mkSystem [selected {services.jellyfin.cacheDir = "/srv/jellyfin-cache";}]).config;
    in
      changed.services.jellyfin.cacheDir == "/srv/jellyfin-cache" && !(changed.systemd.services.jellyfin.serviceConfig ? CacheDirectory);
    essentialDatabase = config.nixstead.serviceRegistry.jellyfin.backup.requiredFiles == ["data/jellyfin.db"];
    customNativeDataBackedUp = let
      changed = (mkSystem [selected {services.jellyfin.dataDir = "/srv/jellyfin-data";}]).config;
    in
      changed.nixstead.serviceRegistry.jellyfin.backup.paths == ["/srv/jellyfin-data"];

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.jellyfin.port = 70000;}]).config.nixstead.services.media.jellyfin.port).success;
  }
