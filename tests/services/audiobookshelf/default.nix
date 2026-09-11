{
  stateful = true;
  paths = ["modules/services/media/audiobookshelf.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent child selection, native listener/path/account overrides, mount ordering and applicable proxy/card/exposure and recovery wiring.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime" "recovery"];
    detail = "One clean encrypted Borg restore of the native application root, followed by HTTP readiness and original marker verification.";
  };
  limitations = ["Focused startup and application-state backup/restore smoke. Library workflows, playback/reading progress, source-content recovery, repeated lifecycle/reboot testing, exhaustive failures, upgrades and ARM runtime are outside this contract."];
}
