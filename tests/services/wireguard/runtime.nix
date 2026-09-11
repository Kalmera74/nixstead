{
  pkgs,
  publicModules,
}:
pkgs.testers.runNixOSTest {
  name = "nixstead-wireguard";
  node.pkgsReadOnly = false;
  requiredFeatures.kvm = false;
  nodes = {
    client = {
      imports = [
        publicModules.wireguard
        (import ../../lib/secret-fixture.nix {
          inherit pkgs;
          generator = ./credentials.py;
        })
      ];
      system.stateVersion = "26.05";
      system.switch.enable = true;
      networking.nftables.enable = true;
      networking.firewall.allowedTCPPorts = [8001];
      nixstead.services.wireguard = {
        enable = true;
        interfaces.work = {
          configFile = "/run/work.conf";
          autostart = false;
        };
        interfaces.unused.enable = false;
        interfaces.keyfile = {
          configFile = "/run/keyfile.conf";
          autostart = false;
        };
        namespaces.apps = {
          sopsSecret = "wireguard/apps";
          autostart = false;
          services = ["vpn-probe"];
        };
      };
      # The host keeps the public configFile contract. This fixture's secret
      # provider renders its runtime path again after reboot.
      sops.secrets."wireguard/work" = {
        path = "/run/work.conf";
        mode = "0400";
      };
      environment.etc."wireguard-credentials.py".source = ./credentials.py;
      systemd.services.vpn-probe.serviceConfig = {
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        DynamicUser = true;
      };
      systemd.services.fixture-host-http = {
        wantedBy = ["multi-user.target"];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8001 --bind ::";
      };
      environment.systemPackages = with pkgs; [wireguard-tools iproute2 util-linux curl dnsutils];
      virtualisation.memorySize = 768;
    };
    peer = {
      system.stateVersion = "26.05";
      networking.firewall.allowedUDPPorts = [51820 53];
      networking.firewall.allowedTCPPorts = [8000 53];
      environment.systemPackages = with pkgs; [wireguard-tools iproute2];
      virtualisation.memorySize = 512;
      services.dnsmasq = {
        enable = true;
        settings = {
          address = ["/fixture.test/10.77.0.1"];
          no-resolv = true;
        };
      };
      systemd.services.fixture-http = {
        wantedBy = ["multi-user.target"];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8000 --bind ::";
      };
    };
  };
  testScript = builtins.readFile ./scenario.py;
}
