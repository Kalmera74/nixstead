{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  cfg =
    (mkSystem [
      {
        nixstead.services.dev.uptimekuma = {
          enable = true;
          port = 23010;
          paths.dataDir = "/srv/uptimekuma";
        };
      }
    ]).config;
  container = cfg.virtualisation.oci-containers.containers.uptimekuma;
in
  serviceContract {
    id = "uptimekuma";
    group = "dev";
    port = 23010;
    nativeEnabled = config: config.virtualisation.oci-containers.containers ? uptimekuma;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.uptimekuma.port = 70000;}]).config.nixstead.services.dev.uptimekuma.port).success;
    invalidImageRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.uptimekuma.images.application = "louislam/uptime-kuma:latest";}]).config.nixstead.services.dev.uptimekuma.images.application).success;
    containerPort = lib.elem "127.0.0.1:23010:3001" container.ports;
    containerVolume = lib.elem "/srv/uptimekuma:/app/data" container.volumes;
    imageFromRegistry = container.image == cfg.nixstead.serviceRegistry.uptimekuma.settings.images.application;
    backupUsesVolume = cfg.nixstead.serviceRegistry.uptimekuma.backup.paths == ["/srv/uptimekuma"];
  }
