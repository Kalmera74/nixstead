{pkgs, ...}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];

  nixstead.host = {
    hostName = "pihole-adapter";
    network.lan = "192.0.2.10";
  };
  nixstead.services.homepage = {
    enable = true;
    port = 22527;
    domain = "dashboard.example.test";
  };
  nixstead.services.pihole = {
    enable = true;
    ip = "127.0.0.2";
    port = 28081;
    domain = "pihole.example.test";
    dnsSync.enable = true;
  };

  systemd.services.pihole-api-fixture = {
    wantedBy = ["multi-user.target"];
    after = ["sops-install-secrets.service"];
    serviceConfig = {
      ExecStartPre = "${pkgs.python3}/bin/python3 /etc/pihole-fixture.py init";
      ExecStart = "${pkgs.python3}/bin/python3 /etc/pihole-fixture.py serve";
      StateDirectory = "pihole-fixture";
    };
  };
  systemd.services.nixstead-pihole-dns-sync = {
    after = ["pihole-api-fixture.service"];
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/nixstead-pihole-dns-sync 0700 root root -"
    ''f /var/lib/nixstead-pihole-dns-sync/managed-domains.json 0600 root root - ["dashboard.example.test","obsolete.example.test"]''
  ];
  environment.etc."pihole-fixture.py".source = ./probe.py;
  system.switch.enable = true;
  virtualisation.memorySize = 1536;
  virtualisation.diskSize = 4096;
}
