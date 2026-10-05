{...}: {
  nixstead.services.productivity.radicale = {
    enable = true;
    port = 25232;
    domain = "calendar.example.test";
    paths.dataDir = "/srv/radicale";
  };
  virtualisation.memorySize = 1024;
  virtualisation.diskSize = 4096;
}
