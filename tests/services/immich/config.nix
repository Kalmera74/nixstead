{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.immich = {
      enable = true;
      port = 28208;
    };
    nixstead.services.media.immich.paths.mediaLocation = "/srv/photos";
    services.immich = {
      user = "photo-owner";
      group = "photo-owner";
      database = {
        name = "photo_db";
        user = "photo_role";
      };
    };
    users.users.photo-owner = {
      isSystemUser = true;
      group = "photo-owner";
    };
    users.groups.photo-owner = {};
  };
  config = (mkSystem [selected]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.immich = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "immich";
    group = "media";
    port = 28208;
    nativeEnabled = c: c.services.immich.enable;
  })
  // {
    nativePort = config.services.immich.port == 28208;
    nativeLoopback = config.services.immich.host == "127.0.0.1";
    publicListener = public.services.immich.host == "0.0.0.0";
    nativeMediaPath = config.services.immich.mediaLocation == "/srv/photos";
    mediaRootOwnership = lib.elem "d /srv/photos 0700 photo-owner photo-owner -" config.systemd.tmpfiles.rules;
    mediaMountDependency = config.systemd.services.immich-server.unitConfig.RequiresMountsFor == ["/srv/photos"];
    backupMediaAndIdentity = config.nixstead.serviceRegistry.immich.backup.paths == ["/srv/photos"] && config.nixstead.serviceRegistry.immich.backup.owner == "photo-owner" && config.nixstead.serviceRegistry.immich.backup.group == "photo-owner";
    backupDatabase = config.nixstead.serviceRegistry.immich.backup.database == "postgresql" && config.nixstead.serviceRegistry.immich.backup.databaseName == "photo_db" && config.nixstead.serviceRegistry.immich.backup.databaseFormat == "custom";
    provisionDistinctDatabaseRole = lib.elem "photo_db" config.services.postgresql.ensureDatabases && lib.any (role: role.name == "photo_role") config.services.postgresql.ensureUsers;
    databaseOwnerSetup = config.systemd.services.postgresql-setup.serviceConfig.ExecStartPost != [];
    missingIdentityRejected = rejects "configured Immich user must exist" {services.immich.user = lib.mkForce "missing-photo-user";};

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.immich.port = 70000;}]).config.nixstead.services.media.immich.port).success;
  }
