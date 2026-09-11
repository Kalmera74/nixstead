{pkgs}: let
  registry = import ../../../modules/services/registry.nix;
  # Parse the production pin so changing it invalidates this fixture's hash.
  parts = builtins.match "(.+):([^:@]+)@(sha256:.+)" registry.uptimekuma.ociImages.application.default;
  imageName = builtins.elemAt parts 0;
  imageTag = builtins.elemAt parts 1;
in {
  reference = "${imageName}:${imageTag}";
  archive = pkgs.dockerTools.pullImage {
    inherit imageName;
    imageDigest = builtins.elemAt parts 2;
    sha256 = "sha256-l/MUlQG3Ufi01La+1Dw56IzY6B4GBfG7o25GvRCeU38=";
    finalImageName = imageName;
    finalImageTag = imageTag;
    os = "linux";
    arch = "amd64";
  };
}
