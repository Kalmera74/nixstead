{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.tubearchivist = {
      enable = true;
      port = 28210;
    };
    nixstead.services.media.tubearchivist.paths = {
      dataDir = "/srv/tube-state";
      mediaDir = "/srv/tube-videos";
    };
  };
  config = (mkSystem [selected]).config;
  namedOwner =
    (mkSystem [
      selected
      {
        nixstead.host.user = {
          name = "archive-owner";
          uid = 28123;
        };
        users.users.archive-owner = {
          isNormalUser = true;
          uid = 28123;
        };
      }
    ]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.tubearchivist = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "tubearchivist";
    group = "media";
    port = 28210;
    nativeEnabled = c: c.virtualisation.oci-containers.containers ? tubearchivist;
  })
  // {
    numericRestoreOwner = config.nixstead.serviceRegistry.tubearchivist.backup.owner == "1000" && config.nixstead.serviceRegistry.tubearchivist.backup.group == "media";
    namedRestoreOwner = namedOwner.nixstead.serviceRegistry.tubearchivist.backup.owner == "archive-owner" && namedOwner.nixstead.serviceRegistry.tubearchivist.backup.group == "media";
    numericOwnerWithoutPersonalAccount = lib.hasInfix "-o 1000 -g media" config.system.activationScripts.tubearchivist-data-dirs.text && !(config.users.users ? nixos);
    existingNamedOwnerPreserved = lib.hasInfix "-o archive-owner -g media" namedOwner.system.activationScripts.tubearchivist-data-dirs.text;
    containerIdentityMatchesSelectedOwner = config.virtualisation.oci-containers.containers.tubearchivist.environment.HOST_UID == "1000" && namedOwner.virtualisation.oci-containers.containers.tubearchivist.environment.HOST_UID == "28123" && config.virtualisation.oci-containers.containers.tubearchivist.environment.HOST_GID == toString config.users.groups.media.gid;
    nativePublishedPort = config.virtualisation.oci-containers.containers.tubearchivist.ports == ["127.0.0.1:28210:8000"];
    publicPublishedPort = public.virtualisation.oci-containers.containers.tubearchivist.ports == ["0.0.0.0:28210:8000"];
    dependenciesNotPublished = config.virtualisation.oci-containers.containers.tubearchivist-es.ports == [] && config.virtualisation.oci-containers.containers.tubearchivist-redis.ports == [];
    nativeDependencies = config.virtualisation.oci-containers.containers.tubearchivist.dependsOn == ["tubearchivist-es" "tubearchivist-redis"];
    nativeVolumes = config.virtualisation.oci-containers.containers.tubearchivist.volumes == ["/srv/tube-videos:/youtube" "/srv/tube-state/cache:/cache"];
    elasticsearchVolume = config.virtualisation.oci-containers.containers.tubearchivist-es.volumes == ["tubearchivist-es-data:/usr/share/elasticsearch/data"];
    runtimeCredentialFiles = config.virtualisation.oci-containers.containers.tubearchivist.environmentFiles == [config.sops.templates."tubearchivist.env".path] && config.virtualisation.oci-containers.containers.tubearchivist-es.environmentFiles == [config.sops.templates."tubearchivist-es.env".path];
    credentialsOutsideEnvironment = !(config.virtualisation.oci-containers.containers.tubearchivist.environment ? TA_PASSWORD) && !(config.virtualisation.oci-containers.containers.tubearchivist-es.environment ? ELASTIC_PASSWORD);
    encryptedRuntimeTemplate = lib.hasInfix config.sops.placeholder."tubearchivist/password" config.sops.templates."tubearchivist.env".content && lib.hasInfix config.sops.placeholder."tubearchivist/elasticPassword" config.sops.templates."tubearchivist-es.env".content;
    snapshotAdapter = config.nixstead.serviceRegistry.tubearchivist.backup.database == "elasticsearch-container" && config.nixstead.serviceRegistry.tubearchivist.backup.databaseContainer == "tubearchivist-es" && config.nixstead.serviceRegistry.tubearchivist.backup.databaseUnit == "docker-tubearchivist-es.service";
    backupUnitsExist = lib.all (unit: config.systemd.services ? ${lib.removeSuffix ".service" unit}) config.nixstead.serviceRegistry.tubearchivist.backup.units;
    separateSnapshotRepository = config.virtualisation.oci-containers.containers.tubearchivist-es.environment."path.repo" == "/usr/share/elasticsearch/data/snapshot,/usr/share/elasticsearch/data/nixstead-snapshots";
    redisIsDisposable = config.virtualisation.oci-containers.containers.tubearchivist-redis.volumes == [] && config.virtualisation.oci-containers.containers.tubearchivist-redis.cmd == ["redis-server" "--save" "" "--appendonly" "no"];
    backupMediaAndCachePaths = config.nixstead.serviceRegistry.tubearchivist.backup.paths == ["/srv/tube-state" "/srv/tube-videos"];
    invalidImageRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.tubearchivist.images.elasticsearch = "elasticsearch:latest";}]).config.nixstead.services.media.tubearchivist.images.elasticsearch).success;

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.tubearchivist.port = 70000;}]).config.nixstead.services.media.tubearchivist.port).success;
  }
