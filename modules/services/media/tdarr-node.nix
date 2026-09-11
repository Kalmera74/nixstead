{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.services.media.tdarr;
  dataDir = config.services.tdarr.dataDir;
  writablePaths = lib.unique (lib.filter (path: path != null) [
    dataDir
    cfg.paths.cacheDir
    cfg.paths.mediaDir
  ]);
in {
  config = lib.mkIf cfg.node {
    services.tdarr = {
      nodes.local.enable = true;
    };

    systemd.services.tdarr-node-local.environment = {
      HOME = "${dataDir}/nodes/local";
      XDG_CACHE_HOME = "${dataDir}/nodes/local/.cache";
      XDG_DATA_HOME = "${dataDir}/nodes/local/.local/share";
    };

    systemd.services.tdarr-node-local.unitConfig.RequiresMountsFor = writablePaths;
    systemd.services.tdarr-node-local.serviceConfig.ReadWritePaths = writablePaths;
  };
}
