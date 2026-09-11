{
  mkSystem,
  lib,
  ...
}: let
  base = {
    nixstead.services.homepage.enable = true;
    nixstead.services.nginx.enable = true;
    nixstead.services.pihole = {
      enable = true;
      ip = "192.0.2.44";
      port = 28006;
      domain = "remote.example.test";
    };
  };
  c = (mkSystem [base]).config;
  disabled = (mkSystem [base {nixstead.services.pihole.enable = lib.mkForce false;}]).config;
  cards = cfg: builtins.toJSON cfg.services.homepage-dashboard.services;
  vhost = c.services.nginx.virtualHosts."remote.example.test";
  card = (builtins.head (lib.filter (section: section ? Infrastructure) c.services.homepage-dashboard.services)).Infrastructure;
  selectedCard = (builtins.head (lib.filter (entry: entry ? "Pi-hole") card))."Pi-hole";
in {
  selectedRemoteAdapter = c.nixstead.serviceRegistry.pihole.enabled && !c.nixstead.serviceRegistry.pihole.local;
  disabledRemovesProxyAndCard = !(disabled.services.nginx.virtualHosts ? "remote.example.test") && !lib.hasInfix (builtins.toJSON "Pi-hole") (cards disabled);
  nativeRemoteProxy = vhost.locations."/admin/".proxyPass == "http://192.0.2.44:28006/admin/" && vhost.locations."/api/".proxyPass == "http://192.0.2.44:28006/api/" && vhost.locations."/".return == "302 /admin/";
  widgetEndpoint = selectedCard.widget.url == "http://192.0.2.44:28006";
  cardDomain = selectedCard.href == "https://remote.example.test/admin/";
  runtimeWidgetSecret = lib.hasInfix "{{HOMEPAGE_VAR_PIHOLEAPIKEY}}" (cards c) && lib.hasInfix c.sops.placeholder."homepage/piholeApiKey" c.sops.templates."homepage.env".content;
  disabledRemovesCredential = !(disabled.sops.secrets ? "homepage/piholeApiKey");
  noLocalUpstreamOrFirewall = !(c.systemd.services ? pihole) && !(c.virtualisation.oci-containers.containers ? pihole) && !(lib.elem 28006 c.networking.firewall.allowedTCPPorts);
  noLocalBackup = c.nixstead.serviceRegistry.pihole.backup == null;
  invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.pihole.port = 65536;}]).config.nixstead.services.pihole.port).success;
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
  dnsMutationRequiresOptIn = !c.nixstead.services.pihole.dnsSync.enable && !(c.systemd.services ? nixstead-pihole-dns-sync) && c.sops.secrets ? "homepage/piholeApiKey";
  explicitDnsCredentialDestination = let
    sync =
      (mkSystem [
        base
        {
          nixstead.services.pihole.dnsSync = {
            enable = lib.mkForce true;
            credentialFile = "/run/credentials/pihole";
          };
        }
      ]).config;
  in
    sync.systemd.services.nixstead-pihole-dns-sync.serviceConfig.LoadCredential == "pihole-password:/run/credentials/pihole" && lib.hasInfix "--prune-managed" sync.systemd.services.nixstead-pihole-dns-sync.serviceConfig.ExecStart;
  invalidDnsCredentialRejected = lib.any (a: !a.assertion && lib.hasInfix "must be an absolute runtime path" a.message) (mkSystem [{nixstead.services.pihole.dnsSync.credentialFile = "relative-password";}]).config.assertions;
  piholeVersion = selectedCard.widget.version == 6;
}
