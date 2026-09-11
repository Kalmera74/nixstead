{
  stateful = true;
  paths = ["modules/services/dev/loki.nix" "modules/services/dev/alloy.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Native single-process Loki starts and reaches its readiness endpoint on the configured loopback listener.";
  };
  limitations = ["History is deliberately disposable in the registry policy and earns no backup claim. Log ingestion/query semantics, retained history, restart/reboot, wall-clock retention deletion, external object storage, distributed operation and cross-version upgrades are unverified by this smoke."];
}
