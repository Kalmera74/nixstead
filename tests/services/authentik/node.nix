{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    (import ../../lib/secret-fixture.nix {
      inherit pkgs;
      generator = ./probe.py;
    })
  ];
  nixstead.services.authentik = {
    enable = true;
    port = 29000;
    workerPort = 29001;
    metricsPort = 29300;
    workerMetricsPort = 29301;
    httpsPort = 29443;
    paths.dataDir = "/srv/identity";
  };
  nixstead.host.network.exposure.services.authentik = "public";
  services.postgresql.settings.port = 25434;
  sops.secrets = lib.genAttrs ["fixture/bootstrapPassword" "fixture/bootstrapToken"] (_: {
    owner = "authentik";
    group = "authentik";
    mode = "0400";
  });
  sops.templates."authentik-bootstrap.env" = {
    owner = "authentik";
    group = "authentik";
    mode = "0400";
    content = ''
      AUTHENTIK_BOOTSTRAP_PASSWORD=${config.sops.placeholder."fixture/bootstrapPassword"}
      AUTHENTIK_BOOTSTRAP_TOKEN=${config.sops.placeholder."fixture/bootstrapToken"}
    '';
  };
  systemd.services = {
    authentik-server.environment = {
      AUTHENTIK_LOG_LEVEL = lib.mkForce "error";
      AUTHENTIK_WEB__WORKERS = "1";
    };
    authentik-worker = {
      environment = {
        AUTHENTIK_LOG_LEVEL = lib.mkForce "error";
      };
      serviceConfig.EnvironmentFile = config.sops.templates."authentik-bootstrap.env".path;
    };
  };
  environment.etc."authentik-probe".source = pkgs.writeShellScript "authentik-probe" ''
    exec ${pkgs.python3}/bin/python3 ${./probe.py} "$@"
  '';
  environment.systemPackages = [pkgs.python3 pkgs.postgresql];
  virtualisation.memorySize = 3072;
  virtualisation.cores = 2;
}
