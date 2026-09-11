{dynamic ? false}: {
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  nixstead.services.productivity.actualbudget = {
    enable = true;
    port = 28289;
  };
  sops.secrets."fixture/serverPassword" = {};
  services.actual = lib.mkIf (!dynamic) {
    user = "budget-owner";
    group = "budget-state";
    settings = {
      dataDir = lib.mkForce "/srv/budget";
      userFiles = "/srv/budget-files";
    };
  };
  users.users.budget-owner = lib.mkIf (!dynamic) {
    isSystemUser = true;
    group = "budget-state";
  };
  users.groups.budget-state = lib.mkIf (!dynamic) {};
  systemd.tmpfiles.rules = lib.optionals (!dynamic) [
    "d /srv/budget 0700 budget-owner budget-state -"
    "d /srv/budget-files 0700 budget-owner budget-state -"
  ];
  environment.etc = {
    "actual-fixture.json".text = builtins.toJSON {
      inherit dynamic;
      inherit (config.services.actual.settings) dataDir serverFiles userFiles;
      version = pkgs.actual-server.version;
    };
    "actual-probe.py".source = ./probe.py;
  };
  environment.systemPackages = [pkgs.python3];
  virtualisation = {
    memorySize = 2048;
    cores = 2;
  };
}
