{pkgs, ...}: {
  nixstead.services.productivity.miniflux = {
    enable = true;
    port = 28190;
  };
  services.postgresql.settings.port = 25432;
  environment.systemPackages = [pkgs.postgresql];
  virtualisation.memorySize = 1536;
}
