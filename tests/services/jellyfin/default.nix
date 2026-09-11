{
  stateful = true;
  paths = ["modules/services/media/jellyfin.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.";
  };
  checks.recovery = {
    systems = ["x86_64-linux"];
    file = ./recovery.nix;
    covers = ["runtime" "recovery"];
    detail = "One clean Borg restore of native application and separate configuration roots, followed by HTTP readiness and independent filesystem markers.";
  };
  limitations = ["Source-media libraries, account/library/playstate workflows, GPU behavior, repeated reboot, detailed failures and upgrades are outside this startup/restore smoke. ARM runtime remains unverified."];
}
