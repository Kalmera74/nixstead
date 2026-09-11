{
  stateful = true;
  paths = ["modules/services/localai/open-webui.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent child selection; local/external backend requirements, custom native listener, runtime credential file, stopped-writer state/key archive and native path override.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    weight = 5;
    covers = ["runtime" "recovery"];
    detail = "Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.";
  };
  limitations = ["Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately."];
}
