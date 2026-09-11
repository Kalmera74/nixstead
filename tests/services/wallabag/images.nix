{pkgs}: let
  registry = import ../../../modules/services/registry.nix;
  hashes = {
    application = "sha256-vLjnqq8P2B0Xs72HRLJoMz2QIg6laZ8yUOIy2xdPYZI=";
    database = "sha256-/BzAL8PawCSmQkpOAn7dc/Bf+q/zdX2U1WqVJr8fi1Y=";
    redis = "sha256-oUQAz5uN5lrbPaMVrLDfYLThbsavlW5n6NSkoKIyHlY=";
  };
in
  builtins.mapAttrs (role: hash: let
    parts = builtins.match "(.+):([^:@]+)@(sha256:.+)" registry.wallabag.ociImages.${role}.default;
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
