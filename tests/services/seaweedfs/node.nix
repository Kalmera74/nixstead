{...}: {
  nixstead.services.dev.seaweedfs = {
    enable = true;
    port = 28888;
    masterPort = 29333;
    paths.dataDir = "/srv/seaweed";
  };
  virtualisation.memorySize = 2048;
}
