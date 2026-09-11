{
  stateful = true;
  paths = ["modules/services/tailscale.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Isolated native daemon, routing mode and advertised routes, no implicit enrollment credentials, invalid routing enum and absence of HTTP proxy/card.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "The native daemon starts, exposes its local socket and reports NeedsLogin with no assigned Tailscale addresses; no control-plane enrollment is performed.";
  };
  limitations = ["Control-plane enrollment/connectivity, enrolled identity continuity and secure identity restore or re-enrollment remain unverified."];
}
