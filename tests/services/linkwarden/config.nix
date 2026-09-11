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
        nixstead.services.productivity.linkwarden = {
          enable = true;
          inherit port;
          paths.dataDir = "/srv/linkwarden";
        };
      }
    ]).config;
  containers = cfg.virtualisation.oci-containers.containers;
  app = containers.linkwarden;
in
  serviceContract {
    id = "linkwarden";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.virtualisation.oci-containers.containers ? linkwarden;
  }
  // {
    nativeListener = lib.elem "127.0.0.1:${toString port}:3000" app.ports;
    nativeVolume = lib.elem "/srv/linkwarden/data:/data/data" app.volumes;
    dependencyOrdering = app.dependsOn == ["linkwarden-db" "linkwarden-meilisearch"];
    runtimeCredentials = lib.elem "/run/secrets/rendered/linkwarden.env" app.environmentFiles;
    backupIncludesApplicationFiles = cfg.nixstead.serviceRegistry.linkwarden.backup.paths == ["/srv/linkwarden"];
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.linkwarden.port = 70000;}]).config.nixstead.services.productivity.linkwarden.port).success;
    invalidImageRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.linkwarden.images.application = "example/application:latest";}]).config.nixstead.services.productivity.linkwarden.images.application).success;
    databaseHandler = cfg.nixstead.serviceRegistry.linkwarden.backup.database == "postgresql-container" && cfg.nixstead.serviceRegistry.linkwarden.backup.databaseName == "linkwarden";
    searchEndpoint = app.environment.MEILI_HOST == "http://linkwarden-meilisearch:7700";
    applicationSecrets = !(app.environment ? NEXTAUTH_SECRET) && !(app.environment ? DATABASE_URL) && lib.hasInfix cfg.sops.placeholder."linkwarden/nextAuthSecret" cfg.sops.templates."linkwarden.env".content;
    searchCredentials = lib.elem "/run/secrets/rendered/linkwarden-meilisearch.env" containers.linkwarden-meilisearch.environmentFiles;
    dependency0Private = containers.linkwarden-db.ports == [];
    dependency0Volume = lib.elem "/srv/linkwarden/postgres:/var/lib/postgresql/data" containers.linkwarden-db.volumes;
    dependency1Private = containers.linkwarden-meilisearch.ports == [];
    dependency1Volume = lib.elem "/srv/linkwarden/meilisearch:/meili_data" containers.linkwarden-meilisearch.volumes;
  }
