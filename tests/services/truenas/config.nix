{
  mkSystem,
  lib,
  ...
}: let
  base = {
    nixstead.services.homepage.enable = true;
    nixstead.services.nginx.enable = true;
    nixstead.services.truenas = {
      enable = true;
      ip = "192.0.2.44";
      port = 28006;
      domain = "remote.example.test";
    };
  };
  c = (mkSystem [base]).config;
  disabled = (mkSystem [base {nixstead.services.truenas.enable = lib.mkForce false;}]).config;
  cards = cfg: builtins.toJSON cfg.services.homepage-dashboard.services;
  vhost = c.services.nginx.virtualHosts."remote.example.test";
  card = (builtins.head (lib.filter (section: section ? Infrastructure) c.services.homepage-dashboard.services)).Infrastructure;
  selectedCard = (builtins.head (lib.filter (entry: entry ? "TrueNAS") card))."TrueNAS";
in {
  selectedRemoteAdapter = c.nixstead.serviceRegistry.truenas.enabled && !c.nixstead.serviceRegistry.truenas.local;
  disabledRemovesProxyAndCard = !(disabled.services.nginx.virtualHosts ? "remote.example.test") && !lib.hasInfix (builtins.toJSON "TrueNAS") (cards disabled);
  nativeRemoteProxy = vhost.locations."/".proxyPass == "http://192.0.2.44:28006";
  widgetEndpoint = selectedCard.widget.url == "http://192.0.2.44:28006";
  cardDomain = selectedCard.href == "https://remote.example.test";
  runtimeWidgetSecret = lib.hasInfix "{{HOMEPAGE_VAR_TRUENASAPIKEY}}" (cards c) && lib.hasInfix c.sops.placeholder."homepage/truenasApiKey" c.sops.templates."homepage.env".content;
  disabledRemovesCredential = !(disabled.sops.secrets ? "homepage/truenasApiKey");
  noLocalUpstreamOrFirewall = !(c.systemd.services ? truenas) && !(c.virtualisation.oci-containers.containers ? truenas) && !(lib.elem 28006 c.networking.firewall.allowedTCPPorts);
  noLocalBackup = c.nixstead.serviceRegistry.truenas.backup == null;
  invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.truenas.port = 65536;}]).config.nixstead.services.truenas.port).success;
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
  websocketProxy = vhost.locations."/".proxyWebsockets;
  noImplicitStorageMount = builtins.attrNames c.fileSystems == ["/"];
}
