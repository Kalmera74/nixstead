{
  pkgs,
  publicModules,
}:
pkgs.testers.runNixOSTest {
  name = "nixstead-nginx-runtime";
  node.pkgsReadOnly = false;
  requiredFeatures.kvm = false;
  globalTimeout = 600;

  nodes = {
    server = {
      imports = [publicModules.default];
      system.stateVersion = "26.05";
      virtualisation.memorySize = 1024;
      environment.systemPackages = [pkgs.openssl];
      nixstead.host = {
        hostName = "nginx-identity";
        network.exposure.services.nginx = "public";
      };
      nixstead.services = {
        nginx.enable = true;
        dev.prometheus = {
          enable = true;
          domain = "metrics.identity.test";
          port = 29091;
        };
      };
      services.nginx.virtualHosts."status.test".locations."/".return = "200 'nginx-ready\\n'";
    };
    client = {
      system.stateVersion = "26.05";
      virtualisation.memorySize = 512;
      environment.systemPackages = [pkgs.curl];
    };
  };

  testScript = ''
    import shlex

    start_all()
    server.wait_for_unit("nginx.service")
    server.wait_for_unit("prometheus.service")
    server.wait_for_open_port(443)
    server.wait_for_open_port(29091)
    certificate = server.succeed("base64 -w0 /var/lib/nginx/local-ca/ca.crt").strip()
    client.succeed("printf %s " + shlex.quote(certificate) + " | base64 -d > /tmp/nginx-ca.crt")
    client.succeed(
        "curl --fail --silent --show-error --connect-timeout 5 --max-time 10 "
        "--cacert /tmp/nginx-ca.crt --resolve metrics.identity.test:443:192.168.1.2 "
        "https://metrics.identity.test/-/healthy"
    )
    client.fail("curl --fail --connect-timeout 3 --max-time 5 http://192.168.1.2:29091/-/healthy")
    server.succeed("ss -ltn | grep -F '127.0.0.1:29091'")
  '';
}
