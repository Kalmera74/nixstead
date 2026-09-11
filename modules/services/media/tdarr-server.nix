{
  config,
  host,
  lib,
  serviceBindAddress,
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
  config = lib.mkIf cfg.server {
    assertions = [
      {
        assertion = cfg.port != cfg.serverPort;
        message = "nixstead.services.media.tdarr.port and serverPort must be different.";
      }
    ];

    services.tdarr = {
      server = {
        enable = true;
        serverIP = serviceBindAddress "tdarr";
        serverBindIP = true;
        serverPort = cfg.serverPort;
        webUIPort = config.nixstead.services.media.tdarr.port;
        openFirewall = false;
      };
    };

    systemd.services.tdarr-server = {
      unitConfig.RequiresMountsFor = writablePaths;
      serviceConfig.ReadWritePaths = writablePaths;
    };
  };
}
