{
  config,
  hardenContainer,
  lib,
  secretPlaceholder,
  servicePublishAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity.linkwarden;
  dataDir = cfg.paths.dataDir;
  dbDir = "${dataDir}/postgres";
  appDataDir = "${dataDir}/data";
  meiliDataDir = "${dataDir}/meilisearch";
in {
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker.enable = true;

    sops.secrets = {
      "linkwarden/nextAuthSecret" = {};
      "linkwarden/postgresPassword" = {};
      "linkwarden/meiliMasterKey" = {};
    };

    sops.templates = {
      "linkwarden-db.env" = {
        content = ''
          POSTGRES_PASSWORD=${secretPlaceholder "linkwarden/postgresPassword"}
        '';
        restartUnits = ["docker-linkwarden-db.service"];
      };
      "linkwarden-meilisearch.env" = {
        content = ''
          MEILI_MASTER_KEY=${secretPlaceholder "linkwarden/meiliMasterKey"}
        '';
        restartUnits = ["docker-linkwarden-meilisearch.service"];
      };
      "linkwarden.env" = {
        content = ''
          NEXTAUTH_SECRET=${secretPlaceholder "linkwarden/nextAuthSecret"}
          DATABASE_URL=postgresql://linkwarden:${secretPlaceholder "linkwarden/postgresPassword"}@linkwarden-db:5432/linkwarden
          MEILI_MASTER_KEY=${secretPlaceholder "linkwarden/meiliMasterKey"}
        '';
        restartUnits = ["docker-linkwarden.service"];
      };
    };

    system.activationScripts.linkwarden-data-dirs = {
      deps = ["users" "groups"];
      text = ''
        install -d -m 0755 -o root -g root ${lib.escapeShellArg dataDir}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg dbDir}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg appDataDir}
        install -d -m 0755 -o root -g root ${lib.escapeShellArg meiliDataDir}
      '';
    };

    virtualisation.oci-containers.containers = {
      linkwarden-db =
        hardenContainer {
          memory = "1g";
          cpus = "1";
          healthCommand = "pg_isready -U linkwarden -d linkwarden";
          healthStartPeriod = "30s";
          readOnlyRootFilesystem = true;
          tmpfs = [
            "/tmp:rw,noexec,nosuid,size=64m"
            "/var/run/postgresql:rw,noexec,nosuid,size=16m"
          ];
        }
        // {
          image = cfg.images.database;
          autoStart = true;
          networks = ["linkwarden-net"];
          volumes = ["${dbDir}:/var/lib/postgresql/data"];
          environmentFiles = [config.sops.templates."linkwarden-db.env".path];
          environment = {
            POSTGRES_DB = "linkwarden";
            POSTGRES_USER = "linkwarden";
          };
        };

      linkwarden-meilisearch =
        hardenContainer {
          memory = "1g";
          cpus = "2";
          healthCommand = "curl -fsS http://127.0.0.1:7700/health >/dev/null";
          readOnlyRootFilesystem = true;
          tmpfs = ["/tmp:rw,noexec,nosuid,size=32m"];
        }
        // {
          image = cfg.images.meilisearch;
          autoStart = true;
          networks = ["linkwarden-net"];
          volumes = ["${meiliDataDir}:/meili_data"];
          environmentFiles = [config.sops.templates."linkwarden-meilisearch.env".path];
        };

      linkwarden =
        hardenContainer {
          memory = "4g";
          cpus = "4";
          pidsLimit = 1024;
          healthCommand = ''node -e "const s=require('net').connect(3000,'127.0.0.1',()=>s.end());s.on('error',()=>process.exit(1))"'';
          healthStartPeriod = "90s";
        }
        // {
          image = cfg.images.application;
          autoStart = true;
          networks = ["linkwarden-net"];
          dependsOn = [
            "linkwarden-db"
            "linkwarden-meilisearch"
          ];
          ports = ["${servicePublishAddress "linkwarden"}:${toString cfg.port}:3000"];
          volumes = ["${appDataDir}:/data/data"];
          environmentFiles = [config.sops.templates."linkwarden.env".path];
          environment = {
            NEXTAUTH_URL = "https://${cfg.domain}/api/v1/auth";
            MEILI_HOST = "http://linkwarden-meilisearch:7700";
            NEXT_PUBLIC_DISABLE_REGISTRATION = "false";
          };
        };
    };
  };
}
