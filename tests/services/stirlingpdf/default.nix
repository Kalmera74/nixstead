{
  stateful = false;
  paths = ["modules/services/productivity/stirling-pdf.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "The native service reaches its configured loopback listener without a systemd restart and serves its HTTP endpoint under the supported stateless profile.";
  };
  limitations = ["The supported profile has authentication and persistent user settings disabled, so temporary processing data is reconstructable and no backup applies. Enabling accounts or retained settings requires a separate persistence/recovery contract." "The runtime check is intentionally a startup/readiness smoke. PDF operations, OCR, office conversion, browser behavior, ARM runtime, large-document performance and upgrades remain unverified."];
}
