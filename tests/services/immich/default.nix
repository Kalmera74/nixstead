{
  stateful = true;
  paths = ["modules/services/media/immich.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    weight = 3;
    covers = ["runtime" "recovery"];
    detail = "One clean combined PostgreSQL/media Borg restore, followed by HTTP readiness and an independent filesystem marker.";
  };
  limitations = ["Photo/album/account workflows, machine learning, external libraries, repeated reboot, detailed failures and upgrades are outside this startup/restore smoke. ARM runtime remains unverified."];
}
