{
  stateful = true;
  paths = ["modules/services/dev/uptimekuma.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Independent enable/disable, parent override, custom port and volume, pinned image and proxy/card/firewall wiring.";
    };
    recovery = {
      systems = ["x86_64-linux"];
      file = ./recovery.nix;
      weight = 4;
      covers = ["runtime" "recovery"];
      detail = "Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.";
    };
  };
  limitations = ["Dedicated service smokes exclude business workflows, failure and restart/reboot matrices, external dependencies and ARM execution. Backup scope is the configured local native state; encrypted runtime credential sources are retained separately."];
}
