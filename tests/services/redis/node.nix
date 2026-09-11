{
  pkgs,
  lib,
  ...
}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  nixstead.services.dev.redis = {
    enable = true;
    port = 26379;
  };
  services.redis.servers."".settings = {
    dir = lib.mkForce "/srv/redis";
    dbfilename = lib.mkForce "suite.rdb";
  };
  systemd.tmpfiles.rules = ["d /srv/redis 0700 redis redis -"];
  environment.etc."redis-probe.py".source = ./probe.py;
  virtualisation.memorySize = 768;
}
