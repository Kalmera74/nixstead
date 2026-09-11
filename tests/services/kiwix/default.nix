{
  stateful = false;
  paths = ["modules/services/media/kiwix.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, child override, custom listener/path settings, native wiring, monitored library regeneration and applicable proxy/card/firewall, credential and backup configuration.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Native Kiwix generates a valid empty catalogue and serves it on the configured loopback listener without a systemd restart.";
  };
  limitations = ["The runtime check is intentionally a fast startup/readiness smoke. Archive loading, full-text search, browser behavior, ARM runtime and upgrades remain unverified." "Source ZIMs remain externally owned; unique archives need a separate storage recovery contract. Only the generated library index is reconstructable, so no backup claim applies."];
}
