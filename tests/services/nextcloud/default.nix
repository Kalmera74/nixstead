{
  stateful = true;
  paths = ["modules/services/productivity/nextcloud.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Independent enable/disable, parent override, custom port, proxy/card, separate home/data and credential override.";
    };
    recovery = {
      file = ./recovery.nix;
      systems = ["x86_64-linux"];
      covers = ["runtime" "recovery"];
      detail = "Initial native startup/readiness, one shipped encrypted Borg backup and clean restore, and the original cheap state marker after recovery.";
    };
  };
  limitations = ["SQLite configuration only; PostgreSQL, external storage, application workflows, repeated lifecycle, failure matrices, upgrades and ARM runtime remain unverified."];
}
