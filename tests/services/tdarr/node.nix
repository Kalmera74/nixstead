{
  lib,
  pkgs,
  ...
}: {
  nixpkgs.config.allowUnfreePredicate = pkg: lib.elem (lib.getName pkg) ["tdarr-server" "tdarr-node"];
  nixstead.services.media.tdarr = {
    server = true;
    node = true;
    port = 28203;
    serverPort = 28213;
    paths.dataDir = "/var/lib/transcode-smoke";
  };
  services.tdarr.nodes.local = {
    startPaused = true;
    workers.transcodeCPU = 0;
    workers.healthcheckCPU = 0;
  };
  environment.systemPackages = [pkgs.python3];
  virtualisation.memorySize = 2048;
}
