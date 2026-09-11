{
  stateful = false;
  paths = ["tests/services/arr-integrations/arr-smoke.nix" "tests/services/arr-integrations/arr-smoke-recovery.nix" "tests/services/arr-integrations/arr-smoke-scenario.py" "tests/services/arr-integrations/arr-smoke-secrets.py" "tests/services/swaparr/image.nix" "modules/services/arr/swaparr.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent target selection, container endpoint/image, runtime-only credentials, no persistent volumes, parent disable and manual Readarr credential wiring.";
  };
  notApplicable = {
    persistence = "This worker owns no durable application records; its runtime/cache is reconstructed.";
    recovery = "Disposable worker state is reconstructed; server state and source bytes belong to separate owners.";
    upgrade = "This worker has no durable application-state migration; compatibility across revisions remains unverified.";
  };
  checks.runtime = {
    file = ../arr-integrations/arr-smoke-recovery.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Shared native ARR startup smoke: configured HTTP readiness, private runtime SOPS credentials, one selected shipped reconciliation and pinned dry-run Swaparr workers; one VM is reused by the family checks.";
  };
  limitations = ["The combined x86_64 ARR smoke passed. Its peer backup/restore activity does not establish Swaparr recovery; worker state is reconstructable. Application business workflows, media acquisition/import, existing queues/libraries, repeated lifecycle, incomplete-input failure matrices and cross-version upgrades are outside this startup fixture. Source/download bytes have separate owners. Runtime targets x86_64; ARM has configuration evaluation only."];
}
