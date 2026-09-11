{
  config,
  lib,
  ociImagesOption,
  optionalRuntimePathOption,
  runtimePathOption,
  serviceOptionFromRegistry,
  serviceRegistry,
  ...
}: let
  cfg = config.nixstead.services.media;
in {
  config.users.groups.${config.nixstead.host.groups.media}.gid = config.nixstead.host.groups.mediaGid;

  options.nixstead.services.media = {
    enable = lib.mkEnableOption "Media stack";
    jellyfin = serviceOptionFromRegistry "jellyfin" {enable = cfg.enable;};
    seerr = serviceOptionFromRegistry "seerr" {
      enable = cfg.enable;
      pathOptions.configDir = runtimePathOption "/var/lib/seerr" "Seerr configuration directory below /var/lib, managed as a private systemd state directory.";
    };
    tdarr = serviceOptionFromRegistry "tdarr" {
      enable = cfg.enable;
      pathOptions = {
        cacheDir = optionalRuntimePathOption "Optional absolute shared Tdarr transcode cache directory made writable to the server and local node.";
        dataDir = optionalRuntimePathOption "Optional absolute Tdarr state directory; the native NixOS default is used when unset.";
        mediaDir = optionalRuntimePathOption "Optional absolute media directory made available to the Tdarr server and local node.";
      };
      extraOptions = {
        server = lib.mkOption {
          type = lib.types.bool;
          default = cfg.tdarr.enable;
          description = "Whether the Tdarr server is enabled.";
        };
        node = lib.mkOption {
          type = lib.types.bool;
          default = cfg.tdarr.enable;
          description = "Whether the local Tdarr processing node is enabled.";
        };
        serverPort = lib.mkOption {
          type = lib.types.port;
          default = serviceRegistry.tdarr.defaults.serverPort;
          description = "Port used by Tdarr nodes to communicate with the server.";
        };
      };
    };
    komga = serviceOptionFromRegistry "komga" {enable = cfg.enable;};
    kavita = serviceOptionFromRegistry "kavita" {
      enable = cfg.enable;
      pathOptions.dataDir = optionalRuntimePathOption "Optional absolute Kavita state directory; the native NixOS default is used when unset.";
      extraOptions.tokenKeyFile = lib.mkOption {
        type = lib.types.path;
        default = "${config.services.kavita.dataDir}/kavita-token-key";
        description = "Runtime file containing Kavita's token-signing key.";
      };
    };
    audiobookshelf = serviceOptionFromRegistry "audiobookshelf" {
      enable = cfg.enable;
      pathOptions.dataDir = optionalRuntimePathOption "Optional absolute Audiobookshelf state directory below /var/lib; the native NixOS default is used when unset.";
    };
    kiwix = serviceOptionFromRegistry "kiwix" {
      enable = cfg.enable;
      pathOptions.dataDir = runtimePathOption "/var/lib/kiwix" "Absolute directory containing Kiwix ZIM files and its generated library index.";
    };
    immich = serviceOptionFromRegistry "immich" {
      enable = cfg.enable;
      pathOptions.mediaLocation = optionalRuntimePathOption "Optional absolute Immich media directory; the native NixOS default is used when unset.";
    };
    romm = serviceOptionFromRegistry "romm" {
      enable = cfg.enable;
      pathOptions = {
        dataDir = runtimePathOption "/var/lib/romm" "Absolute directory containing RomM application state.";
        libraryDir = runtimePathOption "${cfg.romm.paths.dataDir}/library" "Absolute directory containing the ROM library.";
      };
      extraOptions.images =
        ociImagesOption
        (lib.mapAttrs (_: image: image.default) serviceRegistry.romm.ociImages)
        "Digest-pinned OCI images used by RomM.";
    };
    tubearchivist = serviceOptionFromRegistry "tubearchivist" {
      enable = cfg.enable;
      pathOptions = {
        dataDir = runtimePathOption "/var/lib/tubearchivist" "Absolute directory containing TubeArchivist cache state.";
        mediaDir = runtimePathOption "${cfg.tubearchivist.paths.dataDir}/youtube" "Absolute directory containing archived media.";
      };
      extraOptions.images =
        ociImagesOption
        (lib.mapAttrs (_: image: image.default) serviceRegistry.tubearchivist.ociImages)
        "Digest-pinned OCI images used by TubeArchivist.";
    };
  };

  imports = [
    ./jellyfin.nix
    ./seerr.nix
    ./tdarr.nix
    ./komga.nix
    ./kavita.nix
    ./audiobookshelf.nix
    ./kiwix.nix
    ./immich.nix
    ./romm.nix
    ./tubearchivist.nix
  ];
}
