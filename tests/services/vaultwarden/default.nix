{
  stateful = true;
  paths = ["modules/services/vaultwarden.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Isolated native access/signups, runtime admin token, stateVersion-dependent roots and aliases, known SQLite/key requirements, optional private snapshot identity/schedule/mount dependencies, and invalid snapshot profiles.";
    };
    recovery = {
      file = ./recovery.nix;
      systems = ["x86_64-linux"];
      quick = true;
      covers = ["runtime" "recovery"];
      detail = "One shipped encrypted Borg backup and erased-state restore, followed by native readiness and a test-owned file marker checking the configured archive roots.";
    };
  };
  limitations = ["The combined x86_64 startup/recovery smoke passed. Application business workflows, repeated lifecycle/reboots, failure matrices, external integrations and cross-version upgrades are outside this fixture. Runtime/recovery target x86_64; ARM has configuration evaluation only. This fixture uses native SQLite and the legacy stateVersion root; browser/client encryption and native snapshot failure scenarios are outside the maintained smoke."];
}
