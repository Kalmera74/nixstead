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
        nixstead.services.productivity.snapotter = {
          enable = true;
          inherit port;
          paths.dataDir = "/srv/snapotter";
        };
        nixstead.host.user.uid = 1456;
        nixstead.host.groups.mediaGid = 2456;
      }
    ]).config;
  containers = cfg.virtualisation.oci-containers.containers;
  app = containers.snapotter;
in
  serviceContract {
    id = "snapotter";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.virtualisation.oci-containers.containers ? snapotter;
  }
  // {
    nativeListener = lib.elem "127.0.0.1:${toString port}:1349" app.ports;
    nativeVolume = lib.elem "/srv/snapotter/data:/data" app.volumes;
    dependencyOrdering = app.dependsOn == ["snapotter-db" "snapotter-redis"];
    runtimeCredentials = lib.elem "/run/secrets/rendered/snapotter.env" app.environmentFiles;
    backupIncludesApplicationFiles = cfg.nixstead.serviceRegistry.snapotter.backup.paths == ["/srv/snapotter"];
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.snapotter.port = 70000;}]).config.nixstead.services.productivity.snapotter.port).success;
    invalidImageRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.snapotter.images.application = "example/application:latest";}]).config.nixstead.services.productivity.snapotter.images.application).success;
    directoriesUseContainerIdentity = lib.hasInfix "-o 1456 -g 2456 /srv/snapotter/data" cfg.system.activationScripts.snapotter-data-dirs.text && lib.hasInfix "-o 1456 -g 2456 /srv/snapotter/workspace" cfg.system.activationScripts.snapotter-data-dirs.text;
    containerUsesConfiguredIdentity = app.environment.PUID == "1456" && app.environment.PGID == "2456";
    workspaceVolume = lib.elem "/srv/snapotter/workspace:/tmp/workspace" app.volumes;
    authenticationEnabled = app.environment.AUTH_ENABLED == "true";
    applicationSecrets = !(app.environment ? DATA_ENCRYPTION_KEY) && !(app.environment ? DATABASE_URL) && lib.hasInfix cfg.sops.placeholder."snapotter/dataEncryptionKey" cfg.sops.templates."snapotter.env".content;
    redisPersistenceEnabled = lib.hasInfix "--appendonly yes" (lib.concatStringsSep " " containers.snapotter-redis.cmd);
    databaseHandler = cfg.nixstead.serviceRegistry.snapotter.backup.database == "postgresql-container" && cfg.nixstead.serviceRegistry.snapotter.backup.databaseName == "snapotter";
    dependency0Private = containers.snapotter-db.ports == [];
    dependency0Volume = lib.elem "/srv/snapotter/postgres:/var/lib/postgresql/data" containers.snapotter-db.volumes;
    dependency1Private = containers.snapotter-redis.ports == [];
    dependency1Volume = lib.elem "/srv/snapotter/redis:/data" containers.snapotter-redis.volumes;
  }
