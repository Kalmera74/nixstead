{
  stateful = true;
  paths = ["modules/services/productivity/searxng.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.";
    };
    recovery = {
      file = ./recovery.nix;
      systems = ["x86_64-linux"];
      covers = ["runtime" "recovery"];
      detail = "Native SearXNG starts on its loopback listener with a small local engine, then one encrypted backup and clean Borg restore recovers its server secret and query readiness.";
    };
  };
  limitations = ["Owned state is the generated server secret, not search history. The combined startup/recovery check is an intentionally fast service-wiring smoke; public-engine compatibility, ranking, limiter behavior, browser UI and external proxy behavior remain unverified." "Runtime and recovery are x86_64 only; ARM configuration is evaluated separately. Redis is a disposable limiter cache, and no cross-version upgrade is claimed."];
}
