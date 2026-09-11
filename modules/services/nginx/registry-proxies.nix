{
  config,
  lib,
  ...
}: let
  nginxLib = import ./lib.nix {inherit lib;};
  inherit (nginxLib) mkCertPaths mkTlsVhost;

  forwardedHeaders = ''
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Port ${toString config.nixstead.host.ports.https};
  '';

  enabledProxies = lib.filterAttrs (_: entry: entry.enabled && entry.proxy != null) config.nixstead.serviceRegistry;

  mkPiHoleVhost = entry: let
    settings = entry.settings;
    paths = mkCertPaths settings.domain;
    upstream = "http://${settings.ip}:${toString settings.port}";
  in {
    forceSSL = true;
    sslCertificate = paths.cert;
    sslCertificateKey = paths.key;
    locations = {
      "/".return = "302 /admin/";
      "/admin/" = {
        proxyPass = "${upstream}/admin/";
        extraConfig = forwardedHeaders;
      };
      "/api/" = {
        proxyPass = "${upstream}/api/";
        extraConfig = forwardedHeaders;
      };
    };
  };

  mkVhost = _: entry: let
    settings = entry.settings;
    proxy = entry.proxy;
    targetHost =
      if proxy.target == "service"
      then settings.ip
      else "127.0.0.1";
    vhostKey = proxy.vhostKey or settings.domain;
    standardVhost = mkTlsVhost {
      domain = settings.domain;
      upstream = "${proxy.scheme}://${targetHost}:${toString settings.port}";
      proxyWebsockets = proxy.websockets or false;
      forwardedPort = config.nixstead.host.ports.https;
      hostHeader = proxy.hostHeader or "$host";
      extraLocationConfig = proxy.extraLocationConfig or "";
      extraVhostConfig = proxy.extraVhostConfig or "";
    };
    vhost =
      if proxy.kind or "standard" == "pihole"
      then mkPiHoleVhost entry
      else standardVhost // lib.optionalAttrs (vhostKey != settings.domain) {serverName = settings.domain;};
  in {
    name = vhostKey;
    value = vhost;
  };
in {
  # Native applications such as Nextcloud can enable nginx for their own HTTP
  # listener. Managed TLS vhosts require our certificate lifecycle to be enabled.
  config = lib.mkIf config.nixstead.services.nginx.enable {
    services.nginx.virtualHosts = builtins.listToAttrs (lib.mapAttrsToList mkVhost enabledProxies);
  };
}
