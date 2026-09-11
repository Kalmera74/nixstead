{
  stateful = true;
  paths = ["modules/services/dev/gitea.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.";
  };
  checks.recovery = {
    systems = ["x86_64-linux"];
    file = ./recovery.nix;
    covers = ["runtime" "recovery"];
    detail = "One clean Borg restore of native SQLite application and separate repository roots, followed by readiness and independent filesystem markers.";
  };
  limitations = ["Repository, issue and attachment workflows, external databases, SSH, repeated reboot, detailed failures and upgrades are outside this startup/restore smoke. ARM runtime remains unverified."];
}
