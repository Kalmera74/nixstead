{
  config,
  hardenContainer,
  lib,
  servicePublishAddress,
  ...
}: let
  cfg = config.nixstead.services.dev.uptimekuma;
  dataDir = cfg.paths.dataDir;
in {
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker.enable = true;

    system.activationScripts.uptimekuma-data-dirs = {
      deps = [
        "users"
        "groups"
      ];
      text = ''
        install -d -m 0755 -o root -g root ${lib.escapeShellArg dataDir}
      '';
    };

    virtualisation.oci-containers.containers.uptimekuma =
      hardenContainer {
        memory = "512m";
        cpus = "1";
        pidsLimit = 256;
        healthCommand = "extra/healthcheck";
        healthInterval = "60s";
        healthTimeout = "30s";
        healthRetries = 5;
        healthStartPeriod = "180s";
        dropNetRaw = false;
      }
      // {
        image = cfg.images.application;
        autoStart = true;
        ports = ["${servicePublishAddress "uptimekuma"}:${toString cfg.port}:3001"];
        volumes = ["${dataDir}:/app/data"];
      };
  };
}
