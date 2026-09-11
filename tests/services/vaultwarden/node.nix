{
  lib,
  pkgs,
  ...
}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  # Exercise the historical native root; the modern default has C coverage.
  system.stateVersion = lib.mkForce "23.11";
  nixstead.services.vaultwarden = {
    enable = true;
    port = 28222;
    paths.backupDir = "/mnt/vaultsnapshots/vaultwarden";
    backup = {
      user = "root";
      group = "root";
      schedule = "monthly";
    };
  };
  services.vaultwarden.config.LOG_LEVEL = "warn";
  virtualisation.fileSystems."/mnt/vaultsnapshots" = {
    device = "tmpfs";
    fsType = "tmpfs";
  };
  virtualisation.memorySize = 1536;
}
