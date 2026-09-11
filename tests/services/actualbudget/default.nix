{
  stateful = true;
  paths = ["modules/services/productivity/actual-budget.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, native listener/exposure, effective state paths, default DynamicUser and custom account ownership, mount ordering and required recovery inputs.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    weight = 2;
    covers = ["runtime" "recovery"];
    detail = "One clean encrypted Borg restore of custom named-user state and separate budget storage; native readiness, original token and file-marker bytes.";
  };
  checks.recovery-dynamic = {
    file = ./recovery-dynamic.nix;
    systems = ["x86_64-linux"];
    weight = 2;
    covers = ["runtime" "recovery"];
    detail = "Default DynamicUser state backing bytes erased and restored once from Borg, followed by native readiness, original authentication and marker checks.";
  };
  limitations = ["Focused configuration/startup/backup-restore smoke. Budget/transaction workflows, sync failure cases, bank feeds, OIDC, encryption, repeated lifecycle/reboot testing, upgrades and ARM runtime are outside this contract."];
}
