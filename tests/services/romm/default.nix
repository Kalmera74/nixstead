{
  stateful = true;
  paths = ["modules/services/media/romm.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    weight = 6;
    covers = ["runtime" "recovery"];
    detail = "One clean encrypted Borg restore of application paths and native database export into empty application storage and a fresh database volume; application readiness and file markers are checked afterward.";
  };
  limitations = ["Focused startup and backup/restore smoke only; no populated library, account/content workflows, repeated reboot, detailed failures, upgrade or ARM runtime claim. External metadata and internet video/ROM acquisition are outside the fixture."];
}
