{
  pkgs,
  lib,
  ...
}: let
  images = import ./images.nix {inherit pkgs;};
  roles = {
    romm = "application";
    romm-db = "database";
  };
in {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./secrets.py;
    })
  ];
  nixstead.services.media.romm = {
    enable = true;
    domain = "romm.fixture.test";
    port = 28208;
    paths.dataDir = "/srv/romm-smoke";
    paths.libraryDir = "/srv/romm-library";
  };
  virtualisation.oci-containers.containers = lib.mkMerge [
    (lib.mapAttrs (_: role: {
        # Imported archives retain tags; the archive itself uses the production digest.
        image = lib.mkForce images.${role}.reference;
      })
      roles)
    {
      # External catalogue providers are outside this offline startup profile.
      romm.environment = lib.genAttrs [
        "PLAYMATCH_API_ENABLED"
        "LAUNCHBOX_API_ENABLED"
        "HASHEOUS_API_ENABLED"
        "FLASHPOINT_API_ENABLED"
        "HLTB_API_ENABLED"
      ] (_: lib.mkForce "false");
    }
  ];
  systemd.services.romm-fixture-images = {
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
    cores = 4;
  };
}
