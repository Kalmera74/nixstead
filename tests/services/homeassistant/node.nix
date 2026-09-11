{
  pkgs,
  lib,
  ...
}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./client.py;
    })
  ];
  sops.secrets."fixture/homeassistantPassword" = {};
  nixstead.services.homeassistant = {
    enable = true;
    port = 28123;
    paths.dataDir = "/srv/homeassistant-fixture";
  };
  services.home-assistant = {
    extraComponents = ["analytics" "api" "config" "frontend" "http" "onboarding" "person" "recorder" "websocket_api"];
    config = {
      # Native rendering removes null components; retain the wrapper's actual
      # listener/proxy settings while omitting automatic hardware discovery.
      default_config = lib.mkForce null;
      homeassistant = {
        name = "Software fixture";
        latitude = 0.0;
        longitude = 0.0;
        elevation = 0;
        unit_system = "metric";
        time_zone = "UTC";
      };
      frontend = {};
      api = {};
      config = {};
      recorder = {
        commit_interval = 1;
        purge_keep_days = 3;
      };
    };
  };
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "homeassistant-fixture" ''
      exec ${pkgs.python3}/bin/python3 /etc/homeassistant-fixture.py "$@"
    '')
  ];
  environment.etc."homeassistant-fixture.py".source = ./client.py;
  systemd.tmpfiles.rules = [
    "d /srv/homeassistant-fixture 0750 hass hass -"
  ];
  virtualisation.memorySize = 2048;
  virtualisation.diskSize = 4096;
}
