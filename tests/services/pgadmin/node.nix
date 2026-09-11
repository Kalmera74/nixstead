{pkgs, ...}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  nixstead.services.dev = {
    pgadmin = {
      enable = true;
      port = 25050;
    };
    postgresql = {
      enable = true;
      port = 25433;
    };
  };
  services.postgresql.authentication = ''
    host all all 127.0.0.1/32 scram-sha-256
  '';
  services.pgadmin.settings.SQLITE_PATH = "/var/lib/pgadmin/fixture.db";
  virtualisation.memorySize = 2048;
}
