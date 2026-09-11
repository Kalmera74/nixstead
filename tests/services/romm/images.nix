{pkgs}: let
  registry = import ../../../modules/services/registry.nix;
  hashes = {
    application = "sha256-bz5y5feT399w5S6cLc1NDPWBp5U5rVtqzE146Sq3w8U=";
    database = "sha256-Hrzc5ECpremYZJa0Hy6PuaWw9tN6fLPcMwssfZxTU3Y=";
  };
in
  builtins.mapAttrs (role: hash: let
    parts = builtins.match "(.+):([^:@]+)@(sha256:.+)" registry.romm.ociImages.${role}.default;
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
