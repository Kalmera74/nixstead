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
        nixstead.services.productivity.seafile = {
          enable = true;
          inherit port;
          paths.dataDir = "/srv/seafile";
        };
      }
    ]).config;
  containers = cfg.virtualisation.oci-containers.containers;
  app = containers.seafile;
in
  serviceContract {
    id = "seafile";
    group = "productivity";
    inherit port;
    nativeEnabled = c: c.virtualisation.oci-containers.containers ? seafile;
  }
  // {
    nativeListener = lib.elem "127.0.0.1:${toString port}:80" app.ports;
    nativeVolume = lib.elem "/srv/seafile/data:/shared" app.volumes;
    dependencyOrdering = app.dependsOn == ["seafile-db" "seafile-memcached"];
    runtimeCredentials = lib.elem "/run/secrets/rendered/seafile.env" app.environmentFiles;
    backupIncludesApplicationFiles = cfg.nixstead.serviceRegistry.seafile.backup.paths == ["/srv/seafile/data"];
    essentialConfiguration = cfg.nixstead.serviceRegistry.seafile.backup.requiredFiles == ["seafile/conf/ccnet.conf" "seafile/conf/seafile.conf" "seafile/conf/seahub_settings.py"];
    essentialBlocks = lib.elem "seafile/seafile-data/storage/blocks" cfg.nixstead.serviceRegistry.seafile.backup.requiredDirectories;
    privateStateRoot = lib.hasInfix "install -d -m 0700 -o root -g root /srv/seafile" cfg.system.activationScripts.seafile-data-dirs.text;
    nativeCacheHostname = lib.elem "--network-alias=memcached" containers.seafile-memcached.extraOptions;
    recoveredDatabaseAccount = lib.hasInfix "seafile-database-user.py" cfg.systemd.services.docker-seafile.preStart && lib.hasInfix "/srv/seafile/data/seafile/conf/seafile.conf" cfg.systemd.services.docker-seafile.preStart;
    bootstrapCompletesBeforeHttpsRestart = lib.hasInfix "/seafile/conf/admin.txt" cfg.systemd.services.docker-seafile.postStart && lib.hasInfix "curl --max-time 2 -fsS http://127.0.0.1/api2/ping/" cfg.systemd.services.docker-seafile.postStart;
    boundedNativeSeahubStop = lib.hasInfix "seahub_stop_deadline" cfg.systemd.services.docker-seafile.postStart && lib.hasInfix "seahub.sh stop" cfg.systemd.services.docker-seafile.postStart;
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.seafile.port = 70000;}]).config.nixstead.services.productivity.seafile.port).success;
    invalidImageRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.seafile.images.application = "example/application:latest";}]).config.nixstead.services.productivity.seafile.images.application).success;
    backupDatabases = cfg.nixstead.serviceRegistry.seafile.backup.databaseNames == ["ccnet_db" "seafile_db" "seahub_db"];
    databaseHandler = cfg.nixstead.serviceRegistry.seafile.backup.database == "mariadb-container";
    applicationSecrets = !(app.environment ? SEAFILE_ADMIN_PASSWORD) && lib.hasInfix cfg.sops.placeholder."seafile/adminPassword" cfg.sops.templates."seafile.env".content;
    databaseCredentials = lib.elem "/run/secrets/rendered/seafile-db.env" containers.seafile-db.environmentFiles;
    dependency0Private = containers.seafile-db.ports == [];
    dependency0Volume = lib.elem "/srv/seafile/db:/var/lib/mysql" containers.seafile-db.volumes;
    dependency1Private = containers.seafile-memcached.ports == [];
  }
