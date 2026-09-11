{
  stateful = true;
  paths = ["modules/services/media/tdarr.nix" "modules/services/media/tdarr-server.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime" "recovery"];
    detail = "One clean encrypted Borg restore of the stopped native server root, followed by HTTP readiness and an independent marker check.";
  };
  limitations = ["Focused startup and server-state backup/restore smoke; no transcode jobs, media files, detailed node reconnection, repeated reboot or ARM runtime claim."];
}
