{
  mkSystem,
  lib,
  ...
}: let
  base = {
    nixstead.services.nginx.enable = true;
    nixstead.services.localai.ollama = {
      enable = true;
      port = 21434;
      domain = "models.example.test";
    };
    nixstead.host.ports = {
      http = 28080;
      https = 28443;
    };
    nixstead.host.network.exposure.services.nginx = "public";
  };
  c = (mkSystem [base]).config;
  disabled = (mkSystem [{nixstead.services.nginx.enable = false;}]).config;
  childDisabled = (mkSystem [base {nixstead.services.localai.ollama.enable = lib.mkForce false;}]).config;
  proxyDisabled = (mkSystem [base {nixstead.services.nginx.enable = lib.mkForce false;}]).config;
  external =
    (mkSystem [
      base
      {
        nixstead.services.nginx.ca = {
          certificateFile = "/run/secrets/ca.crt";
          privateKeyFile = "/run/secrets/ca.key";
        };
      }
    ]).config;
  rejects = ca: text: lib.any (a: !a.assertion && lib.hasInfix text a.message) (mkSystem [base {nixstead.services.nginx.ca = ca;}]).config.assertions;
in {
  enabledNativeServer = c.services.nginx.enable && c.nixstead.serviceRegistry.nginx.enabled;
  disabledRemovesNativeAndRenewal = !disabled.services.nginx.enable && !(disabled.systemd.services ? nginx-local-certificates) && !(disabled.systemd.timers ? nginx-local-certificates);
  customNativeListeners = c.services.nginx.defaultHTTPListenPort == 28080 && c.services.nginx.defaultSSLListenPort == 28443;
  selectedTlsVhost = c.services.nginx.virtualHosts."models.example.test".forceSSL && c.services.nginx.virtualHosts."models.example.test".locations."/".proxyPass == "http://127.0.0.1:21434";
  childDisableRemovesOnlyVhost = !(childDisabled.services.nginx.virtualHosts ? "models.example.test") && childDisabled.services.nginx.enable;
  disabledProxyRemovesManagedTls = !(proxyDisabled.services.nginx.virtualHosts ? "models.example.test") && proxyDisabled.services.ollama.enable;
  firewallUsesHostPorts = lib.elem 28080 c.networking.firewall.allowedTCPPorts && lib.elem 28443 c.networking.firewall.allowedTCPPorts && !(lib.elem 21434 c.networking.firewall.allowedTCPPorts);
  certificateBeforeListener = lib.elem "nginx-local-certificates.service" c.systemd.services.nginx.requires && lib.elem "sops-install-secrets.service" c.systemd.services.nginx-local-certificates.after;
  scheduledRenewal = c.systemd.timers.nginx-local-certificates.timerConfig.OnCalendar == "daily" && c.systemd.timers.nginx-local-certificates.timerConfig.Persistent;
  noManagedAccountRequired = c.nixstead.services.nginx.ca.homeCertificateFile == null && !c.nixstead.host.user.enable;
  externalKeyStaysRuntimePath = external.nixstead.services.nginx.ca.privateKeyFile == "/run/secrets/ca.key";
  incompleteCaRejected = rejects {certificateFile = "/run/secrets/ca.crt";} "must be set together";
  storeKeyRejected = rejects {
    certificateFile = "/run/secrets/ca.crt";
    privateKeyFile = "/nix/store/plaintext.key";
  } "world-readable Nix store";
  invalidRenewalRejected = rejects {renewBeforeDays = 825;} "less than certificateValidityDays";
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
}
