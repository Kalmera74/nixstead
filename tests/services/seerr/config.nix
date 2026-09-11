{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.seerr = {
      enable = true;
      port = 28202;
    };
    nixstead.services.media.seerr.paths.configDir = "/var/lib/seerr-custom";
  };
  config = (mkSystem [selected]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.seerr = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "seerr";
    group = "media";
    port = 28202;
    nativeEnabled = c: c.services.seerr.enable;
  })
  // {
    nativePort = config.services.seerr.port == 28202;
    nativeLoopback = config.systemd.services.seerr.environment.HOST == "127.0.0.1";
    publicListener = public.systemd.services.seerr.environment.HOST == "0.0.0.0";
    canonicalStateRevision = config.services.seerr.stateRevision == 1;
    nativeState = config.services.seerr.configDir == "/var/lib/seerr-custom" && config.systemd.services.seerr.serviceConfig.StateDirectory == "seerr-custom";
    privateState = config.systemd.services.seerr.serviceConfig.StateDirectoryMode == "0700" && config.nixstead.serviceRegistry.seerr.backup.dynamicUser;
    checkpointFollowsNativeState = lib.hasInfix "/var/lib/seerr-custom/db/db.sqlite3" config.systemd.services.seerr.postStop && lib.hasInfix "wal_checkpoint(TRUNCATE)" config.systemd.services.seerr.postStop;
    backupNativeState = config.nixstead.serviceRegistry.seerr.backup.paths == ["/var/lib/seerr-custom"] && config.nixstead.serviceRegistry.seerr.backup.requiredFiles == ["settings.json" "db/db.sqlite3"];
    backupIntegrity = config.nixstead.serviceRegistry.seerr.backup.requiredJsonFiles == ["settings.json"] && config.nixstead.serviceRegistry.seerr.backup.requiredSQLiteFiles == ["db/db.sqlite3"];
    credentialStatePath = config.nixstead.serviceRegistry.seerr.api.stateFile == "/var/lib/seerr-custom/settings.json";
    relationshipsOptIn = !config.nixstead.services.media.seerr.integrations.enable && !config.nixstead.services.arr.integrations.active;
    outsideStateRejected = rejects "Seerr configDir must" {services.seerr.configDir = lib.mkForce "/srv/seerr";};
    privateStateRejected = rejects "Seerr configDir must" {services.seerr.configDir = lib.mkForce "/var/lib/private/seerr";};
    traversalRejected = rejects "Seerr configDir must" {services.seerr.configDir = lib.mkForce "/var/lib/seerr/../escape";};
    missingJellyfinRejected = rejects "Seerr requires enabled Jellyfin" {
      nixstead.services.media.seerr.integrations = {
        enable = true;
        jellyfin.enable = true;
      };
    };

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.seerr.port = 70000;}]).config.nixstead.services.media.seerr.port).success;
  }
