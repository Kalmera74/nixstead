{
  mkSystem,
  lib,
  ...
}: let
  base = {
    nixstead.services.homepage.enable = true;
    nixstead.services.nginx.enable = true;
    nixstead.services.proxmox = {
      enable = true;
      ip = "192.0.2.44";
      port = 28006;
      domain = "remote.example.test";
    };
  };
  c = (mkSystem [base]).config;
  disabled = (mkSystem [base {nixstead.services.proxmox.enable = lib.mkForce false;}]).config;
  cards = cfg: builtins.toJSON cfg.services.homepage-dashboard.services;
  vhost = c.services.nginx.virtualHosts."remote.example.test";
  card = (builtins.head (lib.filter (section: section ? Infrastructure) c.services.homepage-dashboard.services)).Infrastructure;
  selectedCard = (builtins.head (lib.filter (entry: entry ? "Proxmox") card))."Proxmox";
in {
  selectedRemoteAdapter = c.nixstead.serviceRegistry.proxmox.enabled && !c.nixstead.serviceRegistry.proxmox.local;
  disabledRemovesProxyAndCard = !(disabled.services.nginx.virtualHosts ? "remote.example.test") && !lib.hasInfix (builtins.toJSON "Proxmox") (cards disabled);
  nativeRemoteProxy = vhost.locations."/".proxyPass == "https://192.0.2.44:28006";
  widgetEndpoint = selectedCard.widget.url == "https://192.0.2.44:28006";
  cardDomain = selectedCard.href == "https://remote.example.test";
  runtimeWidgetSecret = lib.hasInfix "{{HOMEPAGE_VAR_PROXMOXPASSWORD}}" (cards c) && lib.hasInfix c.sops.placeholder."homepage/proxmoxPassword" c.sops.templates."homepage.env".content;
  disabledRemovesCredential = !(disabled.sops.secrets ? "homepage/proxmoxPassword");
  noLocalUpstreamOrFirewall = !(c.systemd.services ? proxmox) && !(c.virtualisation.oci-containers.containers ? proxmox) && !(lib.elem 28006 c.networking.firewall.allowedTCPPorts);
  noLocalBackup = c.nixstead.serviceRegistry.proxmox.backup == null;
  invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.proxmox.port = 65536;}]).config.nixstead.services.proxmox.port).success;
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
  websocketProxy = vhost.locations."/".proxyWebsockets;
  tokenUsernameAlsoRuntime = lib.hasInfix "{{HOMEPAGE_VAR_PROXMOXUSERNAME}}" (cards c) && c.sops.secrets ? "homepage/proxmoxUsername";
  configuredSelfSignedRemote = selectedCard.widget.allowInsecure && lib.hasInfix "proxy_ssl_verify off;" vhost.extraConfig;
}
