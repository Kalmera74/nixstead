{
  stateful = true;
  paths = ["modules/services/dev/redis.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.";
  };
  checks.recovery = {
    systems = ["x86_64-linux"];
    file = ./recovery.nix;
    quick = true;
    covers = ["runtime" "recovery"];
    detail = "Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.";
  };
  limitations = ["Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately."];
}
