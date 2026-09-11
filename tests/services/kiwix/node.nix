{...}: let
  dataDir = "/var/lib/kiwix-runtime-fixture";
in {
  nixstead.services.media.kiwix = {
    enable = true;
    port = 28207;
    paths.dataDir = dataDir;
  };

  systemd.tmpfiles.rules = ["d ${dataDir} 0755 root root -"];
  virtualisation.memorySize = 768;
  virtualisation.diskSize = 2048;
}
