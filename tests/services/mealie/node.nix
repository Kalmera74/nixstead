{...}: {
  nixstead.services.productivity.mealie = {
    enable = true;
    port = 28188;
  };
  virtualisation.memorySize = 1536;
}
