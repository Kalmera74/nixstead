{pkgs, ...}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  nixstead.services.dev.postgresql = {
    enable = true;
    port = 25432;
  };
  services.postgresql = {
    dataDir = "/srv/postgresql";
    authentication = ''
      host all all 127.0.0.1/32 scram-sha-256
    '';
  };
  # The native module deliberately provisions only its default directory; a
  # host selecting another path owns provisioning that directory or mount.
  systemd.tmpfiles.rules = ["d /srv/postgresql 0700 postgres postgres -"];
  environment.systemPackages = [pkgs.postgresql];
  environment.etc."postgresql-probe.py".source = ./probe.py;
  virtualisation.memorySize = 1536;
}
