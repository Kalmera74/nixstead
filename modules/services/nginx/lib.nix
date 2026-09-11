{lib}: let
  tlsDir = "/var/lib/nginx/local-ca/certs";

  mkCertPaths = domain: {
    cert = "${tlsDir}/${domain}.crt";
    key = "${tlsDir}/${domain}.key";
  };

  mkTlsVhost = {
    domain,
    upstream,
    proxyWebsockets ? false,
    forwardedPort,
    hostHeader ? "$host",
    extraLocationConfig ? "",
    extraVhostConfig ? "",
  }: let
    paths = mkCertPaths domain;
  in {
    forceSSL = true;
    sslCertificate = paths.cert;
    sslCertificateKey = paths.key;

    locations."/" = {
      proxyPass = upstream;
      inherit proxyWebsockets;
      extraConfig =
        ''
          proxy_set_header Host ${hostHeader};
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-Port ${toString forwardedPort};
        ''
        + extraLocationConfig;
    };

    extraConfig = extraVhostConfig;
  };
in {
  inherit tlsDir mkCertPaths mkTlsVhost;
}
