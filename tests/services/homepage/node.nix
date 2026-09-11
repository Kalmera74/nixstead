{pkgs, ...}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  nixstead.services.homepage = {
    enable = true;
    port = 22525;
    domain = "dashboard.example.test";
    shortcuts = [
      {
        name = "Fixture docs";
        href = "https://docs.example.test";
        description = "Generated shortcut";
      }
    ];
  };
  nixstead.services.truenas = {
    enable = true;
    ip = "127.0.0.2";
    port = 28080;
    domain = "nas.example.internal";
  };
  systemd.services.homepage-truenas-fixture = {
    wantedBy = ["multi-user.target"];
    after = ["sops-install-secrets.service"];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 /etc/homepage-fixture.py serve";
      StateDirectory = "homepage-fixture";
    };
  };
  environment.etc."homepage-fixture.py".source = ./probe.py;
  system.switch.enable = true;
  virtualisation.memorySize = 1536;
  virtualisation.diskSize = 4096;
}
