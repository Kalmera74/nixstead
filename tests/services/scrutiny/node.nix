{...}: {
  nixstead.services.scrutiny = {
    enable = true;
    port = 28192;
    influxdbPort = 28086;
  };
  virtualisation.memorySize = 1536;
}
