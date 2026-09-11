{
  stateful = true;
  paths = ["modules/services/productivity/seafile.nix" "modules/services/productivity/seafile-database-user.py"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, custom listener/state volumes, private dependencies, runtime credentials, all-three-database recovery policy and proxy/card/exposure behavior.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    weight = 5;
    covers = ["runtime" "recovery"];
    detail = "One clean encrypted Borg restore of an empty application tree and MariaDB volume, including all three databases; readiness, initial administrator identity, native configuration and marker bytes.";
  };
  limitations = ["Focused startup and backup/restore smoke for community 11.0.13; library workflows, client synchronization, encrypted libraries, detailed failure matrices, repeated lifecycle/reboot testing, clusters, upgrades and ARM runtime are outside this contract." "SQL preflight checks expected database sections and completion marker, not arbitrary SQL semantics or every individual block."];
}
