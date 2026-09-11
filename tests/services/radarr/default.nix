{
  stateful = true;
  paths = ["tests/services/arr-integrations/arr-smoke.nix" "tests/services/arr-integrations/arr-smoke-recovery.nix" "tests/services/arr-integrations/arr-smoke-scenario.py" "tests/services/arr-integrations/arr-smoke-secrets.py" "tests/services/swaparr/image.nix" "modules/services/arr/radarr.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.";
  };
  checks.recovery = {
    file = ../arr-integrations/arr-smoke-recovery.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime" "recovery"];
    detail = "One shared shipped Borg backup and erased-state restore of selected ARR metadata roots and the reconciliation journal; final readiness and independent test-owned file markers check archive wiring.";
  };
  limitations = ["The combined x86_64 startup/recovery smoke passed. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup/backup fixture. Source/download bytes have separate owners. Runtime/recovery target x86_64; ARM has configuration evaluation only." "The existing /var/lib/radarr archive layout is preserved; custom native dataDir recovery is unverified."];
}
