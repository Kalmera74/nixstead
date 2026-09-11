{pkgs}: let
  registry = import ../../../modules/services/registry.nix;
  parts = builtins.match "(.+):([^:@]+)@(sha256:.+)" registry.swaparr.ociImages.application.default;
  imageName = builtins.elemAt parts 0;
  imageTag = builtins.elemAt parts 1;
in {
  reference = "${imageName}:${imageTag}";
  archive = pkgs.dockerTools.pullImage {
    inherit imageName;
    imageDigest = builtins.elemAt parts 2;
    hash = "sha256-BHAMN4s/doiuL563MLYQ9JRUSJp65y4/pY8FO0wKB9M=";
    finalImageName = imageName;
    finalImageTag = imageTag;
    os = "linux";
    arch = "amd64";
  };
}
