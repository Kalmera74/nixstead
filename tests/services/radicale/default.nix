{
  stateful = true;
  paths = ["modules/services/productivity/radicale.nix"];
  checks = {
    config = {
      file = ./config.nix;
      covers = ["configuration"];
      detail = "Independent enable/disable, parent and full preset selection, custom listener/storage, exposure, proxy/card wiring, DAV discovery, bcrypt authentication, runtime credential override and backup selection.";
    };
    recovery = {
      file = ./recovery.nix;
      systems = ["x86_64-linux"];
      covers = ["runtime" "recovery"];
      detail = "Native startup with generated credentials, authenticated DAV discovery and anonymous denial, followed by one encrypted Borg backup and clean restore of custom storage, a file marker and credential continuity.";
    };
  };
  limitations = ["The recovery fixture covers native startup, authentication and owned files only. Calendar/contact synchronization, external clients, HTTPS discovery, runtime SOPS overrides, credential rotation, ARM runtime and cross-version upgrades remain unverified."];
}
