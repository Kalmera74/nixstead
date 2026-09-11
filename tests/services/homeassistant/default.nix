{
  stateful = true;
  paths = ["modules/services/homeassistant.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Isolated native state/listener/trusted proxy, backup path and mount guard, invalid path and proxy/card/firewall selection.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime" "recovery"];
    detail = "Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.";
  };
  limitations = ["Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately."];
}
