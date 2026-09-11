{
  stateful = true;
  paths = ["modules/services/productivity/miniflux.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Independent enable/disable, parent override, custom listener and PostgreSQL port, invalid port, exposure and card/proxy selection, plus credential override and database ownership/bootstrap wiring.";
    };
    recovery = {
      file = ./recovery.nix;
      systems = ["x86_64-linux"];
      covers = ["runtime" "recovery"];
      detail = "One shipped encrypted Borg backup and erased-state restore, followed by native readiness and SQL and file markers checking the configured archive roots.";
    };
  };
  limitations = ["The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. Recovery retains the independently provisioned PostgreSQL server and role."];
}
