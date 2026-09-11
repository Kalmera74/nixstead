{pkgs}: let
  registry = import ../../../modules/services/registry.nix;
  hashes = {
    application = "sha256-CTvPdt7UPoqDTiMuuk96B5mXXhlHUAA/6ZcJ1ULQmbQ=";
    database = "sha256-9LS5KzESA5OkoytE7bHWKZXIbm0V3bn/7x28vB29d7Y=";
    memcached = "sha256-VIQ7q3htYR54I5yFbHoGAIm/bh1FGOOeIB/dGpu5GgU=";
  };
in
  builtins.mapAttrs (role: hash: let
    parts = builtins.match "(.+):([^:@]+)@(sha256:.+)" registry.seafile.ociImages.${role}.default;
    imageName = builtins.elemAt parts 0;
    imageTag = builtins.elemAt parts 1;
  in {
    reference = "${imageName}:${imageTag}";
    archive = pkgs.dockerTools.pullImage {
      inherit imageName hash;
      imageDigest = builtins.elemAt parts 2;
      finalImageName = imageName;
      finalImageTag = imageTag;
      os = "linux";
      arch = "amd64";
    };
  })
  hashes
