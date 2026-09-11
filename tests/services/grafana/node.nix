{pkgs, ...}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  nixstead.services.dev.grafana = {
    enable = true;
    port = 23001;
    paths.dataDir = "/srv/grafana";
  };
  services.grafana.settings = {
    analytics = {
      reporting_enabled = false;
      check_for_updates = false;
      check_for_plugin_updates = false;
    };
    plugins = {
      preinstall_disabled = true;
      public_key_retrieval_disabled = true;
    };
  };
  virtualisation.memorySize = 2048;
}
