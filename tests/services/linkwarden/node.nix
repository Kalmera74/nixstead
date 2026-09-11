{
  pkgs,
  lib,
  ...
}: let
  images = import ./images.nix {inherit pkgs;};
  roles = {
    linkwarden = "application";
    linkwarden-db = "database";
    linkwarden-meilisearch = "meilisearch";
  };
in {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./secret.py;
    })
  ];

  nixstead.services.productivity.linkwarden = {
    enable = true;
    port = 28219;
    domain = "linkwarden.fixture.test";
  };

  virtualisation.oci-containers.containers =
    lib.mapAttrs (_: role: {
      image = lib.mkForce images.${role}.reference;
    })
    roles;

  systemd.services.linkwarden-fixture-images = {
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
    cores = 4;
    memorySize = 6144;
    diskSize = 20480;
  };
}
