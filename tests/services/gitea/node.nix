{
  pkgs,
  lib,
  ...
}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ../../lib/git-forge-probe.py;
    })
  ];
  nixstead.services.dev.gitea = {
    enable = true;
    port = 23000;
    paths.stateDir = "/srv/gitea-state";
  };
  services.gitea = {
    repositoryRoot = "/srv/gitea-repositories";
    settings = {
      server = {
        ROOT_URL = lib.mkForce "http://127.0.0.1:23000/";
        OFFLINE_MODE = true;
      };
      log.LEVEL = "Warn";
    };
  };
  environment.etc = {
    "git-forge-id".text = "gitea";
    "git-forge-probe.py".source = ../../lib/git-forge-probe.py;
  };
  environment.systemPackages = [pkgs.python3];
  virtualisation.memorySize = 2048;
}
