{
  pkgs,
  lib,
  ...
}: let
  images = (import ./images.nix {inherit pkgs;}) // {elasticsearch = import ./elasticsearch-image.nix {inherit pkgs;};};
  roles = {
    tubearchivist = "application";
    tubearchivist-es = "elasticsearch";
    tubearchivist-redis = "redis";
  };
in {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./secrets.py;
    })
  ];
  nixstead.services.media.tubearchivist = {
    enable = true;
    domain = "tubearchivist.fixture.test";
    port = 28209;
    paths.dataDir = "/srv/tube-smoke";
    paths.mediaDir = "/srv/tube-media";
  };
  virtualisation.oci-containers.containers =
    lib.mapAttrs (_: role: {
      # Imported archives retain tags; the archive itself uses the production digest.
      image = lib.mkForce images.${role}.reference;
    })
    roles;
  systemd.services.tubearchivist-fixture-images = {
    requires = ["docker.service"];
    after = ["docker.service"];
    before = map (name: "docker-${name}.service") (builtins.attrNames roles);
    requiredBy = map (name: "docker-${name}.service") (builtins.attrNames roles);
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.docker];
    script = lib.concatMapStringsSep "\n" (image: ''
      if ! docker image inspect ${lib.escapeShellArg image.reference} >/dev/null 2>&1; then
        docker load --input ${image.archive}
      fi
    '') (builtins.attrValues images);
  };
  virtualisation = {
    memorySize = 4096;
    diskSize = 14336;
    cores = 2;
  };
}
