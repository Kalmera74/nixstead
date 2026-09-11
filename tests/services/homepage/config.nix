{
  mkSystem,
  lib,
  ...
}: let
  base = {
    nixstead.services.homepage = {
      enable = true;
      port = 22525;
      domain = "dashboard.example.test";
      shortcuts = [
        {
          name = "Fixture docs";
          href = "https://docs.example.test";
        }
      ];
    };
    nixstead.services.nginx.enable = true;
    nixstead.services.truenas = {
      enable = true;
      ip = "192.0.2.55";
      port = 28080;
    };
  };
  c = (mkSystem [base]).config;
  disabled = (mkSystem [base {nixstead.services.homepage.enable = lib.mkForce false;}]).config;
  childDisabled = (mkSystem [base {nixstead.services.truenas.enable = lib.mkForce false;}]).config;
  widgetDisabled = (mkSystem [base {nixstead.services.homepage.disabledWidgets = ["truenas"];}]).config;
  exposed = (mkSystem [base {nixstead.host.network.exposure.services.homepage = "public";}]).config;
  cards = cfg: builtins.toJSON cfg.services.homepage-dashboard.services;
in {
  enabledAlone = c.services.homepage-dashboard.enable && !c.nixstead.host.user.enable;
  disabledRemovesImplementation = !disabled.services.homepage-dashboard.enable && !(disabled.sops.templates ? "homepage.env");
  nativeListener = c.services.homepage-dashboard.listenPort == 22525 && c.systemd.services.homepage-dashboard.environment.HOSTNAME == "127.0.0.1";
  allowedHostUsesDomain = lib.hasInfix "dashboard.example.test" c.services.homepage-dashboard.allowedHosts;
  selectedEndpointAndShortcut = lib.hasInfix "http://192.0.2.55:28080" (cards c) && lib.hasInfix "https://docs.example.test" (cards c);
  childDisableRemovesCardAndSecret = !lib.hasInfix (builtins.toJSON "TrueNAS") (cards childDisabled) && !(childDisabled.sops.secrets ? "homepage/truenasApiKey");
  widgetDisablePreservesCard = lib.hasInfix (builtins.toJSON "TrueNAS") (cards widgetDisabled) && !(widgetDisabled.sops.secrets ? "homepage/truenasApiKey") && !lib.hasInfix "HOMEPAGE_VAR_TRUENASAPIKEY" (cards widgetDisabled);
  runtimePlaceholderOnly = lib.hasInfix "{{HOMEPAGE_VAR_TRUENASAPIKEY}}" (cards c) && lib.hasInfix c.sops.placeholder."homepage/truenasApiKey" c.sops.templates."homepage.env".content && c.services.homepage-dashboard.environmentFiles == [c.sops.templates."homepage.env".path];
  proxyTracksCustomPort = c.services.nginx.virtualHosts."dashboard.example.test".locations."/".proxyPass == "http://127.0.0.1:22525";
  disabledRemovesProxy = !(disabled.services.nginx.virtualHosts ? "dashboard.example.test");
  firewallSelection = !(lib.elem 22525 c.networking.firewall.allowedTCPPorts) && lib.elem 22525 exposed.networking.firewall.allowedTCPPorts;
  invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.homepage.port = 65536;}]).config.nixstead.services.homepage.port).success;
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
}
