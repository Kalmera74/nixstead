{...}: {
  nixstead.services.dev.ntfy = {
    enable = true;
    port = 22586;
    domain = "notifications.fixture.test";
    adminUsername = "fixture-admin";
  };
  virtualisation.memorySize = 768;
  virtualisation.diskSize = 4096;
}
