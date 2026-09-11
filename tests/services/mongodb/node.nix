{
  pkgs,
  lib,
  ...
}: let
  python = pkgs.python3.withPackages (ps: [ps.pymongo]);
in {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  nixstead.services.dev.mongodb = {
    enable = true;
    port = 23456;
  };
  services.mongodb = {
    dbpath = "/srv/mongodb-fixture";
    extraConfig = lib.mkAfter ''storage.wiredTiger.engineConfig.cacheSizeGB: 0.25'';
    initialScript = ./initial-script.js;
  };
  environment.systemPackages = [(lib.hiPrio python)];
  environment.etc."mongodb-probe.py".source = ./probe.py;
  systemd.services.mongodb.serviceConfig.TimeoutStartSec = lib.mkForce 300;
  virtualisation.memorySize = 2048;
  virtualisation.cores = 2;
}
