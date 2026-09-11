{...}: {
  nixstead.services.media.jellyfin = {
    enable = true;
    port = 28096;
  };
  services.jellyfin = {
    dataDir = "/srv/jellyfin-state";
    configDir = "/srv/jellyfin-configuration";
  };
  virtualisation.memorySize = 2048;
}
