{...}: {
  nixstead.services.media.audiobookshelf = {
    enable = true;
    port = 28206;
    paths.dataDir = "/var/lib/audiobooks-smoke";
  };
  virtualisation.memorySize = 1536;
}
