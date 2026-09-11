{
  stateful = true;
  paths = [
    "modules/services/dev/mongodb.nix"
    "scripts/lib/validate-mongodb-directory.py"
    "tests/test_mongodb_directory.py"
  ];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent enable/disable, parent override, custom listener, invalid port, exposure and card/proxy selection, plus native application settings and applicable state/credential/dependency wiring.";
  };
  checks.recovery = {
    file = ./recovery.nix;
    systems = ["x86_64-linux"];
    weight = 3;
    covers = ["runtime" "recovery"];
    detail = "Native MongoDB startup with its runtime bootstrap credential, one stopped-WiredTiger encrypted Borg backup and clean restore, and readiness with the exact marker document after recovery.";
  };
  limitations = ["Account/role behavior, credential rotation, failure cases, restart/reboot, replica sets, sharding, alternative storage/encryption settings, exhaustive collection-page integrity, ARM execution and cross-version upgrades are outside this startup/recovery smoke."];
}
