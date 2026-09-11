{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  port = 23456;
  cfg =
    (mkSystem [
      {
        nixstead.services.productivity.wallabag = {
          enable = true;
          inherit port;
          paths.dataDir = "/srv/wallabag";
        };
      }
    ]).config;
  containers = cfg.virtualisation.oci-containers.containers;
  app = containers.wallabag;
in
  serviceContract {
    id = "wallabag";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.virtualisation.oci-containers.containers ? wallabag;
  }
  // {
    nativeListener = lib.elem "127.0.0.1:${toString port}:80" app.ports;
    nativeVolume = lib.elem "/srv/wallabag/images:/var/www/wallabag/web/assets/images" app.volumes;
    dependencyOrdering = app.dependsOn == ["wallabag-db" "wallabag-redis"];
    runtimeCredentials = lib.elem "/run/secrets/rendered/wallabag.env" app.environmentFiles;
    backupIncludesApplicationFiles = cfg.nixstead.serviceRegistry.wallabag.backup.paths == ["/srv/wallabag"];
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.wallabag.port = 70000;}]).config.nixstead.services.productivity.wallabag.port).success;
    invalidImageRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.wallabag.images.application = "example/application:latest";}]).config.nixstead.services.productivity.wallabag.images.application).success;
    databaseHandler = cfg.nixstead.serviceRegistry.wallabag.backup.database == "mariadb-container" && cfg.nixstead.serviceRegistry.wallabag.backup.databaseName == "wallabag";
    registrationDisabled = app.environment.SYMFONY__ENV__FOSUSER_REGISTRATION == "false";
    applicationSecrets = !(app.environment ? SYMFONY__ENV__DATABASE_PASSWORD) && lib.hasInfix cfg.sops.placeholder."wallabag/databasePassword" cfg.sops.templates."wallabag.env".content;
    cacheIsEphemeral = containers.wallabag-redis.volumes == [] && lib.any (option: lib.hasInfix "/data:rw" option) containers.wallabag-redis.extraOptions;
    dependency0Private = containers.wallabag-db.ports == [];
    dependency0Volume = lib.elem "/srv/wallabag/db:/var/lib/mysql" containers.wallabag-db.volumes;
    dependency1Private = containers.wallabag-redis.ports == [];
  }
