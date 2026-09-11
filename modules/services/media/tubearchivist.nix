{
  config,
  hardenContainer,
  lib,
  secretPlaceholder,
  servicePublishAddress,
  ...
}: let
  cfg = config.nixstead.services.media.tubearchivist;
  dataDir = cfg.paths.dataDir;
  mediaDir = cfg.paths.mediaDir;
  cacheDir = "${dataDir}/cache";

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

    sops.secrets = {
      "tubearchivist/username" = {};
      "tubearchivist/password" = {};
      "tubearchivist/elasticPassword" = {};
    };

    sops.templates = {
      "tubearchivist-es.env" = {
        content = ''
          ELASTIC_PASSWORD=${secretPlaceholder "tubearchivist/elasticPassword"}
        '';
        restartUnits = ["docker-tubearchivist-es.service"];
      };
      "tubearchivist.env" = {
        content = ''
          TA_USERNAME=${secretPlaceholder "tubearchivist/username"}
          TA_PASSWORD=${secretPlaceholder "tubearchivist/password"}
          ELASTIC_PASSWORD=${secretPlaceholder "tubearchivist/elasticPassword"}
        '';
        restartUnits = ["docker-tubearchivist.service"];
      };
    };

    system.activationScripts.tubearchivist-data-dirs = {
      deps = ["users" "groups"];
      text = ''
        install -d -m 0775 -o ${lib.escapeShellArg hostUser} -g ${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg dataDir}
        install -d -m 0775 -o ${lib.escapeShellArg hostUser} -g ${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg mediaDir}
        install -d -m 0775 -o ${lib.escapeShellArg hostUser} -g ${lib.escapeShellArg config.nixstead.host.groups.media} ${lib.escapeShellArg cacheDir}
      '';
    };

    virtualisation.oci-containers.containers = {
      tubearchivist-redis =
        hardenContainer {
          memory = "512m";
          cpus = "1";
          pidsLimit = 128;
          healthCommand = "redis-cli ping | grep -q PONG";
          readOnlyRootFilesystem = true;
          tmpfs = ["/tmp:rw,noexec,nosuid,size=32m"];
        }
        // {
          image = cfg.images.redis;
          autoStart = true;
          networks = ["tubearchivist-net"];
          # Redis carries cache and active-task coordination. Durable queued
          # video records are in Elasticsearch; restarting reconstructs cache.
          # Keep persistence disabled so recovery cannot resume stale tasks from
          # a different Elasticsearch snapshot. Existing named volumes are left
          # untouched and can be inspected separately during migration.
          cmd = ["redis-server" "--save" "" "--appendonly" "no"];
        };

      tubearchivist-es =
        hardenContainer {
          memory = "2g";
          cpus = "2";
          pidsLimit = 512;
          healthCommand = ''curl -fsS -u "elastic:$ELASTIC_PASSWORD" http://127.0.0.1:9200/_cluster/health >/dev/null'';
          healthStartPeriod = "60s";
          extraOptions = ["--ulimit=memlock=-1:-1"];
        }
        // {
          image = cfg.images.elasticsearch;
          autoStart = true;
          networks = ["tubearchivist-net"];
          volumes = ["tubearchivist-es-data:/usr/share/elasticsearch/data"];
          environmentFiles = [config.sops.templates."tubearchivist-es.env".path];
          environment = {
            ES_JAVA_OPTS = "-Xms1g -Xmx1g";
            "xpack.security.enabled" = "true";
            "discovery.type" = "single-node";
            # Keep application snapshots and the temporary, unregistered Borg
            # export repositories in separate directories.
            "path.repo" = "/usr/share/elasticsearch/data/snapshot,/usr/share/elasticsearch/data/nixstead-snapshots";
          };
        };

      tubearchivist =
        hardenContainer {
          memory = "2g";
          cpus = "2";
          pidsLimit = 512;
          healthCommand = "curl -fsS http://127.0.0.1:8000/health >/dev/null";
          healthStartPeriod = "60s";
        }
        // {
          image = cfg.images.application;
          autoStart = true;
          dependsOn = [
            "tubearchivist-es"
            "tubearchivist-redis"
          ];
          networks = ["tubearchivist-net"];
          ports = ["${servicePublishAddress "tubearchivist"}:${toString cfg.port}:8000"];
          volumes = [
            "${mediaDir}:/youtube"
            "${cacheDir}:/cache"
          ];
          environmentFiles = [config.sops.templates."tubearchivist.env".path];
          environment = {
            ES_URL = "http://tubearchivist-es:9200";
            REDIS_CON = "redis://tubearchivist-redis:6379";
            HOST_UID = toString config.nixstead.host.user.uid;
            HOST_GID = toString config.nixstead.host.groups.mediaGid;
            TA_HOST = "https://${cfg.domain}";
            TZ = config.nixstead.host.locale.timeZone;
          };
        };
    };
  };
}
