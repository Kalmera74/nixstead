{pkgs, ...}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];

  nixstead.services.homepage = {
    enable = true;
    port = 22526;
    domain = "dashboard.example.test";
  };
  nixstead.services.proxmox = {
    enable = true;
    ip = "127.0.0.2";
    port = 28006;
    domain = "proxmox.example.internal";
  };

  systemd.services.homepage-proxmox-fixture = {
    wantedBy = ["multi-user.target"];
    after = ["sops-install-secrets.service"];
    path = [pkgs.openssl];
    preStart = ''
      if [[ ! -s /var/lib/proxmox-fixture/key.pem || ! -s /var/lib/proxmox-fixture/cert.pem ]]; then
        openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
          -subj /CN=proxmox.example.internal \
          -keyout /var/lib/proxmox-fixture/key.pem \
          -out /var/lib/proxmox-fixture/cert.pem >/dev/null 2>&1
      fi
    '';
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 /etc/proxmox-fixture.py serve";
      StateDirectory = "proxmox-fixture";
    };
  };
  environment.etc."proxmox-fixture.py".source = ./probe.py;
  system.switch.enable = true;
  virtualisation.memorySize = 1536;
  virtualisation.diskSize = 4096;
}
