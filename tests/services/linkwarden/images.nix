{pkgs}: let
  registry = import ../../../modules/services/registry.nix;
  hashes = {
    application = "sha256-YHVkhKtv5CE74bvsRLqxKS5B7O2HyT0JCon0ZVg8dmQ=";
    database = "sha256-n0fOruQ0gUjl5OU3a2xwepHhcAMuwRtwa54bzh6Jg90=";
    meilisearch = "sha256-gbp9BpgV09+v6fsMSk0LF8RcetH2RWeGVQw6YKxp9JM=";
  };
in
  builtins.mapAttrs (role: hash: let
    parts = builtins.match "(.+):([^:@]+)@(sha256:.+)" registry.linkwarden.ociImages.${role}.default;
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
