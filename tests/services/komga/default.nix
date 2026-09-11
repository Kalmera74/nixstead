{
  stateful = true;
  paths = ["modules/services/media/komga.nix"];
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
    detail = "The native service reaches its readiness API, then the shipped backup tool captures initialized state and one clean Borg restore into empty application storage returns the service with an exact smoke marker.";
  };
  limitations = ["The combined startup/recovery check is intentionally a fast service-wiring smoke on x86_64. Accounts, library operations, readers, external authentication, ARM runtime and pinned upgrades remain unverified." "Source books remain externally owned and need their storage owner's recovery contract. Komga's archive covers its own database, settings, indexes and internal task state only."];
}
