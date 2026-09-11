{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity;
in {
  config = lib.mkIf cfg.n8n.enable {
    services.n8n = {
      enable = true;
      openFirewall = false;
      environment = {
        N8N_HOST = serviceBindAddress "n8n";
        N8N_LISTEN_ADDRESS = serviceBindAddress "n8n";
        N8N_PORT = toString config.nixstead.services.productivity.n8n.port;
        N8N_PROTOCOL = "http";
        N8N_SECURE_COOKIE = "true";
        NODE_OPTIONS = "--max-old-space-size=8192";
        WEBHOOK_URL = "https://${config.nixstead.services.productivity.n8n.domain}";
      };
    };
  };
}
