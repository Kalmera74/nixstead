{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.audiobookshelf = {
      enable = true;
      port = 28206;
    };
    nixstead.services.media.audiobookshelf.paths.dataDir = "/var/lib/audiobooks-custom";
  };
  config = (mkSystem [selected]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.audiobookshelf = "public";}]).config;
  native =
    (mkSystem [
      selected
      {
        services.audiobookshelf = {
          dataDir = lib.mkForce "native-books";
          user = "book-owner";
          group = "book-state";
        };
        users.users.book-owner = {
          isSystemUser = true;
          group = "book-state";
        };
        users.groups.book-state = {};
      }
    ]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "audiobookshelf";
    group = "media";
    port = 28206;
    nativeEnabled = c: c.services.audiobookshelf.enable;
  })
  // {
    nativePort = config.services.audiobookshelf.port == 28206;
    nativeLoopback = config.services.audiobookshelf.host == "127.0.0.1";
    publicListener = public.services.audiobookshelf.host == "0.0.0.0";
    nativeStateDirectory = config.services.audiobookshelf.dataDir == "audiobooks-custom";
    backupCustomState = config.nixstead.serviceRegistry.audiobookshelf.backup.paths == ["/var/lib/audiobooks-custom"];
    backupNativeOverride = native.nixstead.serviceRegistry.audiobookshelf.backup.paths == ["/var/lib/native-books"];
    nativeRestoreAccount = native.nixstead.serviceRegistry.audiobookshelf.backup.owner == "book-owner" && native.nixstead.serviceRegistry.audiobookshelf.backup.group == "book-state";
    nativeMountOrdering = native.systemd.services.audiobookshelf.unitConfig.RequiresMountsFor == ["/var/lib/native-books"];
    outsideStateRejected = rejects "directory below /var/lib" {nixstead.services.media.audiobookshelf.paths.dataDir = lib.mkForce "/srv/audiobooks";};
    emptyStateRejected = rejects "directory below /var/lib" {nixstead.services.media.audiobookshelf.paths.dataDir = lib.mkForce "/var/lib/";};

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.audiobookshelf.port = 70000;}]).config.nixstead.services.media.audiobookshelf.port).success;
  }
