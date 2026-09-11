{
  config,
  hardenContainer,
  lib,
  secretPlaceholder,
  servicePublishAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity.wallabag;
  dataDir = cfg.paths.dataDir;
in {
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker.enable = true;

    sops.secrets."wallabag/databasePassword" = {};

    sops.templates = {
      "wallabag-db.env" = {
        content = ''
          MYSQL_ROOT_PASSWORD=${secretPlaceholder "wallabag/databasePassword"}
        '';
        restartUnits = ["docker-wallabag-db.service"];
      };
      "wallabag.env" = {
        content = ''
          MYSQL_ROOT_PASSWORD=${secretPlaceholder "wallabag/databasePassword"}
          SYMFONY__ENV__DATABASE_PASSWORD=${secretPlaceholder "wallabag/databasePassword"}
        '';
        restartUnits = ["docker-wallabag.service"];
      };
    };

    system.activationScripts.wallabag-data-dirs = {
      deps = ["users" "groups"];
      text = ''
        install -d -m 0755 -o root -g root ${lib.escapeShellArg dataDir}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg "${dataDir}/db"}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg "${dataDir}/images"}
      '';
    };

    virtualisation.oci-containers.containers = {
      wallabag-db =
        hardenContainer {
          memory = "1g";
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
          networks = ["wallabag-net"];
          volumes = ["${dataDir}/db:/var/lib/mysql"];
          environmentFiles = [config.sops.templates."wallabag-db.env".path];
        };

      wallabag-redis =
        hardenContainer {
          memory = "256m";
          cpus = "0.5";
          pidsLimit = 128;
          healthCommand = "redis-cli ping | grep -q PONG";
          readOnlyRootFilesystem = true;
          tmpfs = [
            "/data:rw,noexec,nosuid,size=128m"
            "/tmp:rw,noexec,nosuid,size=32m"
          ];
        }
        // {
          image = cfg.images.redis;
          autoStart = true;
          networks = ["wallabag-net"];
        };

      wallabag =
        hardenContainer {
          memory = "1g";
          cpus = "2";
          pidsLimit = 512;
          healthCommand = "php -r '$s = fsockopen(\"127.0.0.1\", 80); exit($s ? 0 : 1);'";
          healthStartPeriod = "60s";
        }
        // {
          image = cfg.images.application;
          autoStart = true;
          networks = ["wallabag-net"];
          dependsOn = [
            "wallabag-db"
            "wallabag-redis"
          ];
          ports = ["${servicePublishAddress "wallabag"}:${toString cfg.port}:80"];
          volumes = ["${dataDir}/images:/var/www/wallabag/web/assets/images"];
          environmentFiles = [config.sops.templates."wallabag.env".path];
          environment = {
            SYMFONY__ENV__DATABASE_DRIVER = "pdo_mysql";
            SYMFONY__ENV__DATABASE_HOST = "wallabag-db";
            SYMFONY__ENV__DATABASE_PORT = "3306";
            SYMFONY__ENV__DATABASE_NAME = "wallabag";
            SYMFONY__ENV__DATABASE_USER = "wallabag";
            SYMFONY__ENV__DATABASE_CHARSET = "utf8mb4";
            SYMFONY__ENV__DOMAIN_NAME = "https://${cfg.domain}";
            SYMFONY__ENV__SERVER_NAME = "Wallabag";
            SYMFONY__ENV__FOSUSER_REGISTRATION = "false";
            SYMFONY__ENV__REDIS_HOST = "wallabag-redis";
            SYMFONY__ENV__REDIS_PORT = "6379";
          };
        };
    };
  };
}
