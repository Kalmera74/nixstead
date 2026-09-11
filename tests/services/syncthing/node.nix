{...}: {
  nixstead.services.syncthing = {
    enable = true;
    port = 28384;
    transferPort = 32000;
    discoveryPort = 31027;
    guiUsername = "fixture-admin";
    paths = {
      dataDir = "/srv/syncthing-data";
      configDir = "/srv/syncthing-state";
    };
  };
  services.syncthing.settings.options = {
    globalAnnounceEnabled = false;
    localAnnounceEnabled = false;
    relaysEnabled = false;
    natEnabled = false;
    urAccepted = -1;
    reconnectionIntervalS = 1;
  };
  virtualisation.memorySize = 768;
  virtualisation.diskSize = 4096;
}
