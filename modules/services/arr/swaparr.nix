{
  config,
  hardenContainer,
  lib,
  secretPlaceholder,
  ...
}: let
  cfg = config.nixstead.services.arr;
  sharedKey = platform: cfg.credentials.enable && platform != "readarr";
  manualPlatforms = lib.filterAttrs (platform: _: !sharedKey platform) platforms;

  mkSwaparrContainer = {
    platform,
    baseUrl,
    environmentFile,
    maxStrikes ? "3",
    scanInterval ? "10m",
    maxDownloadTime ? "6h",
    ignoreAboveSize ? "25GB",
    removeFromClient ? "true",
    strikeQueued ? "false",
    dryRun ? "false",
  }:
    hardenContainer {
      memory = "128m";
      cpus = "0.5";
      pidsLimit = 64;
      # Match the pinned image's native healthy-value check.
      healthCommand = "grep -q 1 /tmp/swaparr.health";
      readOnlyRootFilesystem = true;
      tmpfs = ["/tmp:rw,noexec,nosuid,size=16m"];
    }
    // {
      image = cfg.swaparr.images.application;
      autoStart = true;
      networks = ["host"];
      environmentFiles = [environmentFile];
      environment = {
        BASEURL = baseUrl;
        PLATFORM = platform;
        MAX_STRIKES = maxStrikes;
        SCAN_INTERVAL = scanInterval;
        MAX_DOWNLOAD_TIME = maxDownloadTime;
        IGNORE_ABOVE_SIZE = ignoreAboveSize;
        REMOVE_FROM_CLIENT = removeFromClient;
        STRIKE_QUEUED = strikeQueued;
        DRY_RUN = dryRun;
      };
    };

  platforms = lib.filterAttrs (_: value: value.enabled) {
    radarr = {
      enabled = cfg.radarr.enable;
      port = cfg.radarr.port;
      secret = "radarr/apiKey";
    };
    sonarr = {
      enabled = cfg.sonarr.enable;
      port = cfg.sonarr.port;
      secret = "sonarr/apiKey";
    };
    lidarr = {
      enabled = cfg.lidarr.enable;
      port = cfg.lidarr.port;
      secret = "lidarr/apiKey";
    };
    readarr = {
      enabled = cfg.readarr.enable;
      port = cfg.readarr.port;
      secret = "swaparr/readarrApiKey";
    };
  };
in {
  config = lib.mkIf cfg.swaparr.enable {
    nixstead.services.arr.credentials.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker.enable = true;

    sops.secrets = lib.mapAttrs' (_: value: lib.nameValuePair value.secret {}) manualPlatforms;

    sops.templates = lib.mapAttrs' (platform: value:
      lib.nameValuePair "swaparr-${platform}.env" {
        content = ''
          APIKEY=${secretPlaceholder value.secret}
        '';
        restartUnits = ["docker-swaparr-${platform}.service"];
      })
    manualPlatforms;

    virtualisation.oci-containers.containers = lib.mapAttrs' (platform: value:
      lib.nameValuePair "swaparr-${platform}" (mkSwaparrContainer {
        inherit platform;
        baseUrl = "http://127.0.0.1:${toString value.port}";
        environmentFile =
          if sharedKey platform
          then "/run/nixstead-credentials/${platform}/swaparr.env"
          else config.sops.templates."swaparr-${platform}.env".path;
      }))
    platforms;
  };
}
