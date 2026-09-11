{publicModules}: {lib, ...}: {
  # Canonical revision 1 remains independent of the historical host stateVersion.
  system.stateVersion = lib.mkForce "24.11";
  nixstead.services.media.seerr.enable = true;
  systemd.services.seerr.environment.LOG_LEVEL = "warn";
  virtualisation.memorySize = 2048;
}
