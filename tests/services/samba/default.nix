{
  stateful = true;
  paths = ["modules/services/nas/samba.nix"];
  checks.config = {
    file = ./config.nix;
    covers = ["configuration"];
    detail = "Independent Samba selection, authenticated custom shares/users/read-only policy, explicit firewall, no directory ownership mutation and invalid/reserved share rejection.";
  };
  checks.runtime = {
    file = ./runtime.nix;
    systems = ["x86_64-linux"];
    covers = ["runtime"];
    detail = "Native Samba starts; an authenticated client writes and reads exact bytes through the selected share, while the configured read-only share rejects a write.";
  };
  limitations = ["Samba account-state recovery, credential rotation, guest/unlisted access, missing storage, restart/reboot, owned share recovery, ARM runtime and upgrades remain unverified. Externally owned bytes need their storage owner's recovery fixture."];
}
