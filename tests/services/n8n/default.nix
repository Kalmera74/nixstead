{
  stateful = true;
  paths = ["modules/services/productivity/n8n.nix" "scripts/lib/validate-state-file.py" "tests/test_state_file_validation.py"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, listener/exposure, secure cookies and proxy/card settings; native runtime credential paths and conditional default SQLite/config/encryption-material recovery guards.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    weight = 6;
    covers = ["runtime" "recovery"];
    detail = "Native backend HTTP readiness, one shipped backup and clean Borg restore, and continuity of the original encryption identity and small state marker after deleting the owned directory.";
  };
  limitations = [
    "The fast native SQLite/backend profile does not test workflow internals, encrypted credential use, browser behavior, third-party APIs, queue workers, external database recovery or cross-version upgrades."
    "AArch64 coverage is configuration evaluation only."
  ];
}
