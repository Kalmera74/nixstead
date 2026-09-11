{
  stateful = true;
  paths = ["modules/services/dev/prometheus.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Native Prometheus and node-exporter start, and Prometheus reaches its readiness endpoint on the configured loopback listener.";
  };
  limitations = ["History is deliberately disposable in the registry policy and earns no backup claim. Scraping/query semantics, retained history, restart/reboot, wall-clock retention expiry, remote storage, distributed operation and cross-version upgrades are unverified by this smoke; native runtime coverage is x86_64 only."];
}
