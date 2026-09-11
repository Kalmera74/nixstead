{
  mkSystem,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.tdarr = {
      node = true;
      server = false;
      paths = {
        dataDir = "/var/lib/node-state";
        cacheDir = "/srv/transcode-cache";
        mediaDir = "/srv/media";
      };
    };
  };
  config = (mkSystem [selected]).config;
  disabled = (mkSystem [selected {nixstead.services.media.tdarr.node = lib.mkForce false;}]).config;
  parent =
    (mkSystem [
      {
        nixstead.services.media.tdarr = {
          enable = true;
          node = false;
        };
      }
    ]).config;
  custom =
    (mkSystem [
      selected
      {
        services.tdarr.user = "transcoder";
        users.users.transcoder = {
          isSystemUser = true;
          group = "transcoder";
        };
        users.groups.transcoder = {};
      }
    ]).config;
  remote =
    (mkSystem [
      selected
      {
        services.tdarr.nodes.local = {
          serverURL = "http://transcode-peer.invalid:28213";
          environmentFile = "/run/secrets/tdarr-node-env";
        };
      }
    ]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in {
  validSystem = builtins.isString (mkSystem [selected]).config.system.build.toplevel.drvPath;
  independentNode = config.nixstead.serviceRegistry.tdarr-node.enabled && config.services.tdarr.nodes.local.enable && !config.services.tdarr.server.enable;
  disabledRemovesImplementation = !disabled.nixstead.serviceRegistry.tdarr-node.enabled && !(disabled.systemd.services ? tdarr-node-local);
  parentAllowsChildDisable = !parent.nixstead.serviceRegistry.tdarr-node.enabled && !(parent.systemd.services ? tdarr-node-local) && parent.services.tdarr.server.enable;
  customServerConnection = remote.systemd.services.tdarr-node-local.environment.serverURL == "http://transcode-peer.invalid:28213";
  runtimeAuthenticationFile = remote.systemd.services.tdarr-node-local.serviceConfig.EnvironmentFile == "/run/secrets/tdarr-node-env" && !(remote.systemd.services.tdarr-node-local.environment ? apiKey);
  nativeDataPath = config.services.tdarr.dataDir == "/var/lib/node-state";
  writableMediaAndCache = lib.all (path: lib.elem path config.systemd.services.tdarr-node-local.serviceConfig.ReadWritePaths && lib.elem path config.systemd.services.tdarr-node-local.unitConfig.RequiresMountsFor) ["/var/lib/node-state" "/srv/transcode-cache" "/srv/media"];
  isolatedNodeHome = config.systemd.services.tdarr-node-local.environment.HOME == "/var/lib/node-state/nodes/local" && config.systemd.services.tdarr-node-local.environment.XDG_CACHE_HOME == "/var/lib/node-state/nodes/local/.cache";
  customNativeIdentity = custom.systemd.services.tdarr-node-local.serviceConfig.User == "transcoder";
  noInboundListenerOrCard = config.nixstead.serviceRegistry.tdarr-node.proxy == null && config.nixstead.serviceRegistry.tdarr-node.homepage == null && config.nixstead.serviceRegistry.tdarr-node.listeners.settingsTcpPorts == [];
  noDisposableCacheBackup = config.nixstead.serviceRegistry.tdarr-node.backup == null;
  missingIdentityRejected = rejects "configured Tdarr user must exist" {services.tdarr.user = "missing-transcoder";};
}
