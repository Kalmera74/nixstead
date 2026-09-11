{
  stateful = true;
  paths = ["modules/services/syncthing.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Isolated child/native GUI/peer selection, transfer/discovery firewall, state/index/credential destinations, bootstrap order, unowned folders and identity-only archive.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    covers = ["runtime" "recovery"];
    systems = ["x86_64-linux"];
    detail = "Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.";
  };
  limitations = ["Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately."];
}
