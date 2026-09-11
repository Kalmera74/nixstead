{
  config,
  hardenContainer,
  lib,
  secretPlaceholder,
  servicePublishAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity.snapotter;
  dataDir = cfg.paths.dataDir;
  appDataDir = "${dataDir}/data";
  workspaceDir = "${dataDir}/workspace";
  dbDir = "${dataDir}/postgres";
  redisDir = "${dataDir}/redis";
in {
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker.enable = true;

    sops.secrets = {
      "snapotter/defaultPassword" = {};
      "snapotter/dataEncryptionKey" = {};
      "snapotter/postgresPassword" = {};
      "snapotter/redisPassword" = {};
    };

    sops.templates = {
      "snapotter-db.env" = {
        content = ''
          POSTGRES_PASSWORD=${secretPlaceholder "snapotter/postgresPassword"}
        '';
        restartUnits = ["docker-snapotter-db.service"];
      };
      "snapotter.env" = {
        content = ''
          DEFAULT_PASSWORD=${secretPlaceholder "snapotter/defaultPassword"}
          DATA_ENCRYPTION_KEY=${secretPlaceholder "snapotter/dataEncryptionKey"}
          DATABASE_URL=postgres://snapotter:${secretPlaceholder "snapotter/postgresPassword"}@snapotter-db:5432/snapotter
          REDIS_URL=redis://:${secretPlaceholder "snapotter/redisPassword"}@snapotter-redis:6379
        '';
        restartUnits = ["docker-snapotter.service"];
      };
      "snapotter-redis.env" = {
        content = ''
          REDIS_PASSWORD=${secretPlaceholder "snapotter/redisPassword"}
        '';
        restartUnits = ["docker-snapotter-redis.service"];
      };
    };

    system.activationScripts.snapotter-data-dirs = {
      deps = ["users" "groups"];
      text = ''
        install -d -m 0755 -o root -g root ${lib.escapeShellArg dataDir}
        install -d -m 0770 -o ${toString config.nixstead.host.user.uid} -g ${toString config.nixstead.host.groups.mediaGid} ${lib.escapeShellArg appDataDir}
        install -d -m 0770 -o ${toString config.nixstead.host.user.uid} -g ${toString config.nixstead.host.groups.mediaGid} ${lib.escapeShellArg workspaceDir}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg dbDir}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg redisDir}
      '';
    };

    virtualisation.oci-containers.containers = {
      snapotter-db =
        hardenContainer {
          memory = "1g";
          cpus = "1";
          pidsLimit = 256;
          healthCommand = "pg_isready -U snapotter -d snapotter";
          healthInterval = "10s";
          healthTimeout = "5s";
          healthRetries = 12;
          healthStartPeriod = "15s";
          readOnlyRootFilesystem = true;
          tmpfs = [
            "/tmp:rw,noexec,nosuid,size=64m"
            "/var/run/postgresql:rw,noexec,nosuid,size=16m"
          ];
        }
        // {
          image = cfg.images.database;
          autoStart = true;
          networks = ["snapotter-net"];
          volumes = ["${dbDir}:/var/lib/postgresql/data"];
          environmentFiles = [config.sops.templates."snapotter-db.env".path];
          environment = {
            POSTGRES_DB = "snapotter";
            POSTGRES_USER = "snapotter";
          };
        };

      snapotter-redis =
        hardenContainer {
          memory = "768m";
          cpus = "1";
          pidsLimit = 128;
          healthCommand = ''redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping | grep -q PONG'';
          healthInterval = "10s";
          healthTimeout = "5s";
          healthRetries = 12;
          healthStartPeriod = "10s";
          readOnlyRootFilesystem = true;
          tmpfs = ["/tmp:rw,noexec,nosuid,size=32m"];
        }
        // {
          image = cfg.images.redis;
          autoStart = true;
          networks = ["snapotter-net"];
          volumes = ["${redisDir}:/data"];
          environmentFiles = [config.sops.templates."snapotter-redis.env".path];
          cmd = [
            "sh"
            "-c"
            ''exec redis-server --maxmemory-policy noeviction --maxmemory 512mb --appendonly yes --requirepass "$REDIS_PASSWORD"''
          ];
        };

      snapotter =
        hardenContainer {
          memory = "4g";
          cpus = "4";
          pidsLimit = 1024;
          healthCommand = "curl -fsS --max-time 5 http://127.0.0.1:1349/api/v1/health >/dev/null";
          healthTimeout = "10s";
          healthStartPeriod = "90s";
          extraOptions = ["--shm-size=2g"];
        }
        // {
          image = cfg.images.application;
          autoStart = true;
          networks = ["snapotter-net"];
          dependsOn = [
            "snapotter-db"
            "snapotter-redis"
          ];
          ports = ["${servicePublishAddress "snapotter"}:${toString cfg.port}:1349"];
          volumes = [
            "${appDataDir}:/data"
            "${workspaceDir}:/tmp/workspace"
          ];
          environmentFiles = [config.sops.templates."snapotter.env".path];
          environment = {
            AUTH_ENABLED = lib.boolToString cfg.auth.enable;
            DEFAULT_USERNAME = "admin";
            SKIP_MUST_CHANGE_PASSWORD = "false";
            EMBEDDED = "0";
            TRUST_PROXY = "loopback,linklocal,uniquelocal";
            PUID = toString config.nixstead.host.user.uid;
            PGID = toString config.nixstead.host.groups.mediaGid;
            TZ = config.nixstead.host.locale.timeZone;
            MAX_UPLOAD_SIZE_MB = "500";
            MAX_BATCH_SIZE = "100";
            RATE_LIMIT_PER_MIN = "1000";
          };
        };
    };
  };
}
