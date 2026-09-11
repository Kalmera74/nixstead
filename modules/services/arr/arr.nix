{
  config,
  lib,
  ociImagesOption,
  optionalRuntimePathOption,
  serviceOptionFromRegistry,
  serviceRegistry,
  ...
}: let
  cfg = config.nixstead.services.arr;
in {
  config.users.groups.${config.nixstead.host.groups.media}.gid = config.nixstead.host.groups.mediaGid;

  options.nixstead.services.arr = {
    enable = lib.mkEnableOption "ARR stack";

    sonarr = serviceOptionFromRegistry "sonarr" {enable = cfg.enable;};
    radarr = serviceOptionFromRegistry "radarr" {enable = cfg.enable;};
    lidarr = serviceOptionFromRegistry "lidarr" {enable = cfg.enable;};
    readarr = serviceOptionFromRegistry "readarr" {enable = false;};
    bazarr = serviceOptionFromRegistry "bazarr" {enable = cfg.enable;};
    prowlarr = serviceOptionFromRegistry "prowlarr" {enable = cfg.enable;};
    sabnzbd = serviceOptionFromRegistry "sabnzbd" {
      enable = false;
      pathOptions.dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/sabnzbd";
        description = "Private SABnzbd application state.";
      };
      extraOptions.secretFile = optionalRuntimePathOption "Optional runtime INI file for Usenet server and WebUI credentials; use a SOPS secret path.";
    };
    shelfmark = serviceOptionFromRegistry "shelfmark" {
      enable = false;
      pathOptions.ingestDir = optionalRuntimePathOption "Explicit book acquisition output directory, separate from existing library management.";
      extraOptions.integrations = {
        enable = lib.mkEnableOption "Shelfmark connection defaults using shared runtime credentials";
        prowlarr = lib.mkOption {
          type = lib.types.bool;
          default = cfg.shelfmark.integrations.enable && cfg.prowlarr.enable;
          description = "Supply authenticated Prowlarr connection defaults.";
        };
        qbittorrent = lib.mkOption {
          type = lib.types.bool;
          default = cfg.shelfmark.integrations.enable && cfg.qbittorrent.enable;
          description = "Supply authenticated qBittorrent connection defaults.";
        };
      };
    };
    swaparr = serviceOptionFromRegistry "swaparr" {
      enable = cfg.enable;
      extraOptions.images =
        ociImagesOption
        (lib.mapAttrs (_: image: image.default) serviceRegistry.swaparr.ociImages)
        "Digest-pinned OCI images used by Swaparr.";
    };
    qbittorrent = serviceOptionFromRegistry "qbittorrent" {
      enable = cfg.enable;
      extraOptions = {
        usernameFile = optionalRuntimePathOption "Optional declared SOPS file for the canonical qbittorrent/username entry.";
        passwordFile = optionalRuntimePathOption "Optional declared SOPS plaintext password file; the native hash is derived at startup.";
      };
      pathOptions = {
        savePath = optionalRuntimePathOption "Optional absolute download destination; qBittorrent's own default is used when unset.";
        tempPath = optionalRuntimePathOption "Optional absolute incomplete-download directory; qBittorrent's own default is used when unset.";
      };
    };
  };

  imports = [
    ./shelfmark.nix
    ./sabnzbd.nix
    ./storage.nix
    ./credentials.nix
    ./monitoring.nix
    ./integrations.nix
    ./vpn.nix
    ./sonarr.nix
    ./radarr.nix
    ./lidarr.nix
    ./readarr.nix
    ./bazarr.nix
    ./prowlarr.nix
    ./swaparr.nix
    ./qbittorrent.nix
  ];
}
