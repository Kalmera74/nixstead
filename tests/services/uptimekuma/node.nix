{
  pkgs,
  lib,
  ...
}: let
  image = import ./image.nix {inherit pkgs;};
in {
  nixstead.services.dev.uptimekuma = {
    enable = true;
    port = 23010;
    paths.dataDir = "/srv/uptimekuma";
  };
  virtualisation.oci-containers.containers.uptimekuma = {
    image = lib.mkForce image.reference;
    imageFile = image.archive;
  };
}
