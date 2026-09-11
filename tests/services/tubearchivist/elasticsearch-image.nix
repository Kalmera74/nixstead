{pkgs}: let
  registry = import ../../../modules/services/registry.nix;
  parts = builtins.match "(.+):([^:@]+)@(sha256:.+)" registry.tubearchivist.ociImages.elasticsearch.default;
  imageName = builtins.elemAt parts 0;
  imageTag = builtins.elemAt parts 1;
in {
  reference = "${imageName}:${imageTag}";
  archive = pkgs.dockerTools.pullImage {
    inherit imageName;
    imageDigest = builtins.elemAt parts 2;
    sha256 = "sha256-shRcHXF7zh1ApOwDntbqBlUgjGmMNZSvQNl/QI7zOLM=";
    finalImageName = imageName;
    finalImageTag = imageTag;
    os = "linux";
    arch = "amd64";
  };
}
