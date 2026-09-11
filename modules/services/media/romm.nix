{
  config,
  hardenContainer,
  lib,
  secretPlaceholder,
  servicePublishAddress,
  ...
}: let
  cfg = config.nixstead.services.media.romm;
  dataDir = cfg.paths.dataDir;
  libraryDir = cfg.paths.libraryDir;
  resourcesDir = "${dataDir}/resources";
  assetsDir = "${dataDir}/assets";
  configDir = "${dataDir}/config";

  # POSIX ownership accepts a numeric UID without creating a personal account.
  # Keep configured container identities usable for independently enabled modules.
  hostUser =
    if builtins.hasAttr config.nixstead.host.user.name config.users.users
    then config.nixstead.host.user.name
    else toString config.nixstead.host.user.uid;
in {
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker.enable = true;

    sops.secrets = lib.genAttrs (map (name: "romm/${name}") [
      "authSecretKey"
      "dbPassword"
      "dbRootPassword"
      "igdbClientId"
      "igdbClientSecret"
      "mobyGamesApiKey"
      "screenscraperUser"
      "screenscraperPassword"
      "steamGridDbApiKey"
      "retroAchievementsApiKey"
    ]) (_: {});

    sops.templates = {
      "romm-db.env" = {
        content = ''
          MARIADB_ROOT_PASSWORD=${secretPlaceholder "romm/dbRootPassword"}
          MARIADB_PASSWORD=${secretPlaceholder "romm/dbPassword"}
        '';
        restartUnits = ["docker-romm-db.service"];
      };
      "romm.env" = {
        content = ''
          ROMM_AUTH_SECRET_KEY=${secretPlaceholder "romm/authSecretKey"}
          DB_PASSWD=${secretPlaceholder "romm/dbPassword"}
          IGDB_CLIENT_ID=${secretPlaceholder "romm/igdbClientId"}
          IGDB_CLIENT_SECRET=${secretPlaceholder "romm/igdbClientSecret"}
          MOBYGAMES_API_KEY=${secretPlaceholder "romm/mobyGamesApiKey"}
          SCREENSCRAPER_USER=${secretPlaceholder "romm/screenscraperUser"}
          SCREENSCRAPER_PASSWORD=${secretPlaceholder "romm/screenscraperPassword"}
          STEAMGRIDDB_API_KEY=${secretPlaceholder "romm/steamGridDbApiKey"}
          RETROACHIEVEMENTS_API_KEY=${secretPlaceholder "romm/retroAchievementsApiKey"}
        '';
        restartUnits = ["docker-romm.service"];
      };
    };

    system.activationScripts.romm-data-dirs = {
      deps = ["users" "groups"];
      text = ''
        install -d -m 0775 -o ${lib.escapeShellArg hostUser} -g ${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg dataDir}
        chown ${lib.escapeShellArg hostUser}:${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg dataDir}

        install -d -m 0775 -o ${lib.escapeShellArg hostUser} -g ${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg resourcesDir}
        chown -R ${lib.escapeShellArg hostUser}:${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg resourcesDir}

        install -d -m 0775 -o ${lib.escapeShellArg hostUser} -g ${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg assetsDir}
        chown -R ${lib.escapeShellArg hostUser}:${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg assetsDir}

        install -d -m 0775 -o ${lib.escapeShellArg hostUser} -g ${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg configDir}
        chown -R ${lib.escapeShellArg hostUser}:${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg configDir}

        install -d -m 0775 -o ${lib.escapeShellArg hostUser} -g ${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg libraryDir}
        chgrp ${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg libraryDir}
        chmod 0775 ${lib.escapeShellArg libraryDir}
      '';
    };

    virtualisation.oci-containers.containers = {
      romm-db =
        hardenContainer {
          memory = "2g";
          cpus = "1";
          healthCommand = "healthcheck.sh --connect --innodb_initialized";
          healthStartPeriod = "30s";
          readOnlyRootFilesystem = true;
          tmpfs = [
            "/run/mysqld:rw,noexec,nosuid,size=64m"
            "/tmp:rw,noexec,nosuid,size=64m"
          ];
        }
        // {
          image = cfg.images.database;
          autoStart = true;
          networks = ["romm-net"];
          volumes = ["romm-db-data:/var/lib/mysql"];
          environmentFiles = [config.sops.templates."romm-db.env".path];
          environment = {
            MARIADB_DATABASE = "romm";
            MARIADB_USER = "romm";
          };
        };

      romm =
        hardenContainer {
          memory = "4g";
          cpus = "4";
          pidsLimit = 512;
          healthCommand = "python -c 'import urllib.request; urllib.request.urlopen(\"http://127.0.0.1:8080/api/heartbeat\", timeout=5)'";
          healthStartPeriod = "60s";
        }
        // {
          image = cfg.images.application;
          autoStart = true;
          networks = ["romm-net"];
          dependsOn = [
            "romm-db"
          ];
          ports = ["${servicePublishAddress "romm"}:${toString cfg.port}:8080"];
          volumes = [
            "${resourcesDir}:/romm/resources"
            "${assetsDir}:/romm/assets"
            "${libraryDir}:/romm/library"
            "romm-redis-data:/redis-data"
            "${configDir}:/romm/config"
          ];
          environmentFiles = [config.sops.templates."romm.env".path];
          environment = {
            TZ = config.nixstead.host.locale.timeZone;
            ROMM_BASE_URL = "https://${cfg.domain}";
            ROMM_PORT = "8080";
            ROMM_DB_DRIVER = "mariadb";
            DB_HOST = "romm-db";
            DB_PORT = "3306";
            DB_NAME = "romm";
            DB_USER = "romm";
            REFRESH_RETROACHIEVEMENTS_CACHE_DAYS = "30";

            PLAYMATCH_API_ENABLED = "true";
            LAUNCHBOX_API_ENABLED = "true";
            HASHEOUS_API_ENABLED = "true";
            FLASHPOINT_API_ENABLED = "true";
            HLTB_API_ENABLED = "true";
          };
        };
    };
  };
}
