{
  stateful = true;
  paths = ["modules/services/nas/"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent NAS children, explicit data/parity devices, mergerfs mount dependency, SnapRAID parity/content configuration and missing-disk assertions.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Three disposable native filesystems and the configured mergerfs pool mount successfully, and one bounded writer can create and read exact bytes through the pool.";
  };
  limitations = ["SnapRAID sync/scrub/repair, missing-mount handling, restart/reboot, independent backup, multiple-disk loss, physical devices and authenticated sharing integration remain unverified by the maintained smoke. Parity is not an independent archive recovery contract."];
}
