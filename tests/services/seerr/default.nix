{
  stateful = true;
  paths = ["modules/services/media/seerr.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent selection, child override, custom listener/path settings, native wiring and applicable proxy/card/firewall, credential and backup configuration; no runtime claim.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime" "recovery"];
    detail = "One clean Borg restore of canonical private application state, followed by native HTTP readiness and an independent filesystem marker.";
  };
  limitations = ["Accounts, movie/TV requests, external Jellyfin/TMDB/ARR peers, repeated reboot, detailed failures and upgrades are outside this startup/restore smoke. ARM runtime remains unverified."];
}
