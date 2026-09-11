{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.media.romm = {
      enable = true;
      port = 28209;
    };
    nixstead.services.media.romm.paths = {
      dataDir = "/srv/romm-state";
      libraryDir = "/srv/rom-library";
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
  public = (mkSystem [selected {nixstead.host.network.exposure.services.romm = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
  custom = (mkSystem [selected {nixstead.services.media.romm.images.application = "example.invalid/romm:test@sha256:0000000000000000000000000000000000000000000000000000000000000000";}]).config;
in
  (serviceContract {
    id = "romm";
    group = "media";
    port = 28209;
    nativeEnabled = c: c.virtualisation.oci-containers.containers ? romm;
  })
  // {
    numericRestoreOwner = config.nixstead.serviceRegistry.romm.backup.owner == "1000" && config.nixstead.serviceRegistry.romm.backup.group == "media";
    namedRestoreOwner = namedOwner.nixstead.serviceRegistry.romm.backup.owner == "archive-owner" && namedOwner.nixstead.serviceRegistry.romm.backup.group == "media";
    numericOwnerWithoutPersonalAccount = lib.hasInfix "-o 1000 -g media" config.system.activationScripts.romm-data-dirs.text && !(config.users.users ? nixos);
    existingNamedOwnerPreserved = lib.hasInfix "-o archive-owner -g media" namedOwner.system.activationScripts.romm-data-dirs.text;
    nativePublishedPort = config.virtualisation.oci-containers.containers.romm.ports == ["127.0.0.1:28209:8080"];
    publicPublishedPort = public.virtualisation.oci-containers.containers.romm.ports == ["0.0.0.0:28209:8080"];
    databaseNotPublished = config.virtualisation.oci-containers.containers.romm-db.ports == [];
    databaseDependency = config.virtualisation.oci-containers.containers.romm.dependsOn == ["romm-db"];
    nativeVolumes = lib.all (volume: lib.elem volume config.virtualisation.oci-containers.containers.romm.volumes) ["/srv/romm-state/resources:/romm/resources" "/srv/romm-state/assets:/romm/assets" "/srv/rom-library:/romm/library" "/srv/romm-state/config:/romm/config"];
    runtimeCredentialFiles = config.virtualisation.oci-containers.containers.romm.environmentFiles == [config.sops.templates."romm.env".path] && config.virtualisation.oci-containers.containers.romm-db.environmentFiles == [config.sops.templates."romm-db.env".path];
    credentialsOutsideEnvironment = !(config.virtualisation.oci-containers.containers.romm.environment ? DB_PASSWD) && !(config.virtualisation.oci-containers.containers.romm.environment ? ROMM_AUTH_SECRET_KEY) && !(config.virtualisation.oci-containers.containers.romm-db.environment ? MARIADB_PASSWORD);
    encryptedRuntimeTemplate = lib.hasInfix config.sops.placeholder."romm/dbPassword" config.sops.templates."romm.env".content && lib.hasInfix config.sops.placeholder."romm/authSecretKey" config.sops.templates."romm.env".content;
    backupStateAndSourceLibrary = config.nixstead.serviceRegistry.romm.backup.paths == ["/srv/romm-state" "/srv/rom-library"];
    scopedDatabaseBackup = config.nixstead.serviceRegistry.romm.backup.database == "mariadb-container" && config.nixstead.serviceRegistry.romm.backup.databaseContainer == "romm-db" && config.nixstead.serviceRegistry.romm.backup.databaseName == "romm";
    customImage = custom.virtualisation.oci-containers.containers.romm.image == "example.invalid/romm:test@sha256:0000000000000000000000000000000000000000000000000000000000000000";
    invalidImageRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.romm.images.application = "romm:latest";}]).config.nixstead.services.media.romm.images.application).success;

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.media.romm.port = 70000;}]).config.nixstead.services.media.romm.port).success;
  }
