{
  stateful = true;
  paths = ["modules/services/productivity/linkwarden.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent enable/disable and parent override, custom published listener/state volumes, private dependencies, runtime SOPS templates, backup database wiring, proxy/card/firewall and invalid port/image inputs.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    weight = 4;
    covers = ["runtime" "recovery"];
    detail = "Pinned application and dependency startup with runtime SOPS credentials, HTTP readiness, one shipped PostgreSQL/Borg backup and clean restore, and the original file marker after recovery.";
  };
  limitations = ["No business workflow, search/queue correctness, failure or restart/reboot matrix, cross-version upgrade, or ARM runtime claim. Runtime SOPS sources remain outside the application backup and must be retained independently."];
}
