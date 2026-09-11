{
  pkgs,
  lib,
  ...
}: let
  images = import ./images.nix {inherit pkgs;};
  roles = {
    seafile = "application";
    seafile-db = "database";
    seafile-memcached = "memcached";
  };
in {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  nixstead.services = {
    productivity.seafile = {
      enable = true;
      domain = "seafile.fixture.test";
      port = 28224;
      paths.dataDir = "/srv/seafile";
    };
    nginx.enable = true;
  };
  networking.hosts."127.0.0.1" = ["seafile.fixture.test"];
  virtualisation.oci-containers.containers =
    lib.mapAttrs (_: role: {
      # Docker archives retain tags instead of registry RepoDigests. Each
      # imported image still comes from the exact production digest and hash.
      image = lib.mkForce images.${role}.reference;
    })
    roles;
  # Software-emulated coldplug can starve Docker's bounded internal containerd
  # startup. Finish device discovery before starting the real container engine.
  systemd.services.docker = {
    wants = ["systemd-udev-settle.service"];
    after = ["systemd-udev-settle.service"];
  };
  systemd.services.seafile-fixture-images = {
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
  environment.etc."seafile-probe.py".source = ./probe.py;
  environment.systemPackages = [pkgs.python3 pkgs.openssl];
  virtualisation = {
    cores = 2;
    memorySize = 4096;
    diskSize = 14336;
  };
}
