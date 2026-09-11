{
  stateful = true;
  paths = ["tests/services/arr-integrations/arr-smoke.nix" "tests/services/arr-integrations/arr-smoke-recovery.nix" "tests/services/arr-integrations/arr-smoke-scenario.py" "tests/services/arr-integrations/arr-smoke-secrets.py" "tests/services/swaparr/image.nix" "modules/services/arr/integrations.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Opt-in relationships, independently disabled targets, ownership-journal identity, runtime-only credentials, backup manifest and missing dependency/storage assertions.";
  };
  checks.recovery = {
    file = ./arr-smoke-recovery.nix;
    systems = ["x86_64-linux"];
    weight = 6;
    covers = ["runtime" "recovery"];
    detail = "One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.";
  };
  limitations = ["The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only."];
}
