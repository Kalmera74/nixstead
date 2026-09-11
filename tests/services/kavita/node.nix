{...}: {
  nixstead.services.media.kavita = {
    enable = true;
    port = 28205;
    paths.dataDir = "/var/lib/kavita-smoke";
  };
  virtualisation.memorySize = 1536;
}
