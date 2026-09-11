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
  cfg = config.nixstead.services.productivity;
in {
  options.nixstead.services.productivity = {
    enable = lib.mkEnableOption "Productivity stack";
    paperless = serviceOptionFromRegistry "paperless" {
      enable = cfg.enable;
      pathOptions = {
        dataDir = optionalRuntimePathOption "Optional absolute Paperless state directory; the native NixOS default is used when unset.";
        mediaDir = optionalRuntimePathOption "Optional absolute Paperless media directory; the native NixOS default is derived from dataDir when unset.";
        consumeDir = optionalRuntimePathOption "Optional absolute Paperless consumption directory; the native NixOS default is derived from dataDir when unset.";
      };
    };
    nextcloud = serviceOptionFromRegistry "nextcloud" {
      enable = cfg.enable;
      pathOptions.dataDir = optionalRuntimePathOption "Optional absolute Nextcloud data directory; the native NixOS default is used when unset.";
      extraOptions.adminPasswordFile = optionalRuntimePathOption "Optional absolute file containing the Nextcloud administrator password, such as a sops-nix secret path; a password is generated when unset.";
    };
    n8n = serviceOptionFromRegistry "n8n" {enable = cfg.enable;};
    stirlingpdf = serviceOptionFromRegistry "stirlingpdf" {enable = cfg.enable;};
    seafile = serviceOptionFromRegistry "seafile" {
      enable = cfg.enable;
      pathOptions.dataDir = runtimePathOption "/var/lib/seafile" "Absolute directory containing Seafile's container state.";
      extraOptions.images =
        ociImagesOption
        (lib.mapAttrs (_: image: image.default) serviceRegistry.seafile.ociImages)
        "Digest-pinned OCI images used by Seafile.";
    };
    wallabag = serviceOptionFromRegistry "wallabag" {
      enable = cfg.enable;
      pathOptions.dataDir = runtimePathOption "/var/lib/wallabag" "Absolute directory containing Wallabag container state.";
      extraOptions.images =
        ociImagesOption
        (lib.mapAttrs (_: image: image.default) serviceRegistry.wallabag.ociImages)
        "Digest-pinned OCI images used by Wallabag.";
    };
    linkwarden = serviceOptionFromRegistry "linkwarden" {
      enable = cfg.enable;
      pathOptions.dataDir = runtimePathOption "/var/lib/linkwarden" "Absolute directory containing Linkwarden container state.";
      extraOptions.images =
        ociImagesOption
        (lib.mapAttrs (_: image: image.default) serviceRegistry.linkwarden.ociImages)
        "Digest-pinned OCI images used by Linkwarden.";
    };
    snapotter = serviceOptionFromRegistry "snapotter" {
      enable = cfg.enable;
      pathOptions.dataDir = runtimePathOption "/var/lib/snapotter" "Absolute directory containing SnapOtter container state.";
      extraOptions.auth.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether SnapOtter requires users to authenticate.";
      };
      extraOptions.images =
        ociImagesOption
        (lib.mapAttrs (_: image: image.default) serviceRegistry.snapotter.ociImages)
        "Digest-pinned OCI images used by SnapOtter.";
    };
    mealie = serviceOptionFromRegistry "mealie" {
      enable = cfg.enable;
      pathOptions.dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/mealie";
        readOnly = true;
        description = "Native Mealie state directory.";
      };
    };
    actualbudget = serviceOptionFromRegistry "actualbudget" {
      enable = cfg.enable;
      pathOptions.dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/actual";
        readOnly = true;
        description = "Native Actual Budget state directory.";
      };
    };
    miniflux = serviceOptionFromRegistry "miniflux" {
      enable = cfg.enable;
      pathOptions.dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/miniflux";
        readOnly = true;
        description = "Directory containing Miniflux runtime-generated bootstrap credentials.";
      };
      extraOptions.adminCredentialsFile = optionalRuntimePathOption "Optional absolute environment file containing ADMIN_USERNAME and ADMIN_PASSWORD, such as a sops-nix template path; credentials are generated when unset.";
    };
    searxng = serviceOptionFromRegistry "searxng" {
      enable = cfg.enable;
      pathOptions.dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/searxng";
        readOnly = true;
        description = "Directory containing SearXNG runtime-generated secrets.";
      };
    };
  };

  imports = [
    ./paperless.nix
    ./nextcloud.nix
    ./n8n.nix
    ./stirling-pdf.nix
    ./seafile.nix
    ./wallabag.nix
    ./linkwarden.nix
    ./snapotter.nix
    ./mealie.nix
    ./actual-budget.nix
    ./miniflux.nix
    ./searxng.nix
  ];
}
