{
  pkgs,
  lib,
  ...
}: {
  nixstead.services.productivity.n8n = {
    enable = true;
    port = 23467;
    domain = "n8n.fixture.test";
  };
  services.n8n = {
    package = import ./package.nix {inherit pkgs;};
    environment = {
      # Exercise the native backend without generating unused browser assets.
      N8N_DISABLE_UI = true;
      NODE_OPTIONS = lib.mkForce "--max-old-space-size=1536";
      DB_SQLITE_POOL_SIZE = 1;
      N8N_TEMPLATES_ENABLED = false;
      N8N_PERSONALIZATION_ENABLED = false;
    };
  };
  environment.systemPackages = [pkgs.python3];
  environment.etc."n8n-probe.py".source = ./probe.py;
  systemd.tmpfiles.rules = ["d /var/lib/n8n-fixture 0700 root root -"];
  virtualisation.memorySize = 3072;
  virtualisation.cores = 2;
}
