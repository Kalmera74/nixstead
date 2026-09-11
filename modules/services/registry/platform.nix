{
  mkService,
  localProxy,
  health,
  setup,
  hostSetup,
  credential,
  ...
}: {
  homepage = mkService {
    name = "Homepage";
    optionPath = ["homepage"];
    defaults = {
      subdomain = "home";
      port = 2525;
    };
    firewall = true;
    proxy = localProxy;
    health = health "homepage-dashboard.service";
    secrets = ["homepage"];
    setup =
      ((setup "platform" 620 ["media-starter" "media-server" "development" "full"])
        // {
          label = "Homepage dashboard";
          requiresLan = false;
        })
      // {
        support = "VM startup and credential coverage; no application restore claim";
        requirements = "Small dashboard; widgets need runtime credentials";
      };
  };

  nginx = mkService {
    name = "Nginx";
    optionPath = ["nginx"];
    listeners.hostTcpPorts = ["http" "https"];
    firewall.hostTcpPorts = ["http" "https"];
    health = (health "nginx.service") // {hostPort = "http";};
    setup =
      ((setup "platform" 610 ["media-starter" "media-server" "development" "full"])
        // {
          label = "Nginx reverse proxy";
          requiresLan = false;
        })
      // {
        support = "VM proxy coverage; CA trust journey test defined";
        requirements = "DNS records and client CA trust required; preserve or rotate the local CA on recovery";
      };
  };

  tailscale = mkService {
    name = "Tailscale";
    optionPath = ["tailscale"];
    health = (health "tailscaled.service") // {protocol = "none";};
    setup =
      (setup "platform" 630 ["minimal" "media-server" "development" "full"])
      // {requiresLan = false;};
  };

  wireguard = mkService {
    name = "WireGuard";
    optionPath = ["wireguard"];
    credentials = [
      (credential.manual "Declare host interfaces or isolated namespaces with a runtime configFile or SOPS key. Peer configuration and keys remain outside the Nix store.")
    ];
    # Multiple named tunnels have separate units and secret sources. Configure
    # them in Nix; there is no aggregate listener, state backup or setup toggle.
  };

  cifs = mkService {
    name = "CIFS";
    optionPath = ["cifs"];
    secrets = ["cifs"];
    credentials = [
      (credential.sops "username" ["cifs" "username"])
      (credential.sops "password" ["cifs" "password"])
      (credential.sops "domain" ["cifs" "domain"])
    ];
    setup = hostSetup 740 "CIFS/SMB client mounts";
  };

  nas = mkService {
    name = "NAS";
    optionPath = ["nas"];
    setup = hostSetup 750 "Local NAS stack (discovered data and parity disks)";
  };

  samba = mkService {
    name = "Samba";
    optionPath = ["nas" "samba"];
    listeners = {
      tcpPorts = [139 445];
      udpPorts = [137 138];
    };
    firewall = {
      tcpPorts = [139 445];
      udpPorts = [137 138];
    };
  };
}
