{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.tdarr = {
      server = true;
      node = false;
      port = 28203;
      serverPort = 28213;
      paths = {
        dataDir = "/var/lib/transcode";
        cacheDir = "/srv/transcode-cache";
        mediaDir = "/srv/media";
      };
    };
  };
  config = (mkSystem [selected]).config;
  custom =
    (mkSystem [
      selected
      {
        services.tdarr.user = "transcoder";
        services.tdarr.server.environmentFile = "/run/secrets/tdarr-server-env";
        users.users.transcoder = {
          isSystemUser = true;
          group = "transcoder";
        };
        users.groups.transcoder = {};
      }
    ]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.tdarr = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "tdarr";
    group = "media";
    port = 28203;
    nativeEnabled = c: c.services.tdarr.server.enable;
  })
  // {
    independentServer = config.services.tdarr.server.enable && !(config.services.tdarr.nodes ? local);
    nativeListeners = config.services.tdarr.server.webUIPort == 28203 && config.services.tdarr.server.serverPort == 28213 && config.services.tdarr.server.serverIP == "127.0.0.1";
    publicListeners = public.services.tdarr.server.serverIP == "0.0.0.0" && lib.all (port: lib.elem port public.networking.firewall.allowedTCPPorts) [28203 28213];
    backupServerOnly = config.nixstead.serviceRegistry.tdarr.backup.paths == ["/var/lib/transcode/server"] && config.nixstead.serviceRegistry.tdarr.backup.units == ["tdarr-server.service"];
    backupNativeIdentity = custom.nixstead.serviceRegistry.tdarr.backup.owner == "transcoder" && custom.nixstead.serviceRegistry.tdarr.backup.group == custom.services.tdarr.group;
    requiredServerConfiguration = config.nixstead.serviceRegistry.tdarr.backup.requiredFiles == ["configs/Tdarr_Server_Config.json"];
    nativeDataPath = config.services.tdarr.dataDir == "/var/lib/transcode";
    writableMediaAndCache = lib.all (path: lib.elem path config.systemd.services.tdarr-server.serviceConfig.ReadWritePaths && lib.elem path config.systemd.services.tdarr-server.unitConfig.RequiresMountsFor) ["/var/lib/transcode" "/srv/transcode-cache" "/srv/media"];
    runtimeAuthenticationFile = custom.systemd.services.tdarr-server.serviceConfig.EnvironmentFile == "/run/secrets/tdarr-server-env" && !(custom.systemd.services.tdarr-server.environment ? authSecretKey);
    customNativeIdentity = custom.systemd.services.tdarr-server.serviceConfig.User == "transcoder";
    conflictingListenersRejected = rejects "port and serverPort must be different" {nixstead.services.media.tdarr.serverPort = lib.mkForce 28203;};
    missingIdentityRejected = rejects "configured Tdarr user must exist" {services.tdarr.user = "missing-transcoder";};
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.tdarr.serverPort = 70000;}]).config.nixstead.services.media.tdarr.serverPort).success;
  }
