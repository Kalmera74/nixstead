{
  stateful = true;
  paths = ["modules/services/dev/pgadmin.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Independent enable/disable, parent override, custom listener, exposure and card/proxy selection, native credential/package wiring, and local SQLite recovery inputs following a supported custom filename.";
    };
    recovery = {
      file = ./recovery.nix;
      systems = ["x86_64-linux"];
      covers = ["runtime" "recovery"];
      detail = "One shipped encrypted Borg backup and erased-state restore, followed by native readiness and a test-owned file marker checking the configured archive roots.";
    };
  };
  limitations = ["The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. Managed PostgreSQL databases have a separate recovery owner."];
}
