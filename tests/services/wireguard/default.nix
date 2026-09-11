{
  stateful = false;
  paths = ["modules/services/wireguard.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Host and namespace selection, private SOPS rotation, explicit handshake firewall, bound service lifecycle, child disable and missing/ambiguous/unsafe source rejection.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    quick = true;
    covers = ["runtime"];
    detail = "A real local peer plus the host and application-namespace tunnels start from runtime private configuration; both routes and namespace DNS reach the peer.";
  };
  limitations = ["Commercial providers, general VPN-server routing/NAT, key rotation, tunnel loss, restart/reboot, encrypted-source loss, runtime autostart and ARM execution are outside this smoke; no archive of runtime interfaces is claimed."];
}
