{
  config,
  lib,
  pkgs,
  runtimePathOption,
  secretPath,
  serviceBindAddress,
  serviceOptionFromRegistry,
  serviceRegistry,
  ...
}: let
  cfg = config.nixstead.services.authentik;
  serviceUser = "authentik";
  serviceGroup = "authentik";

  commonEnvironment = {
    AUTHENTIK_POSTGRESQL__HOST = "/run/postgresql";
    AUTHENTIK_POSTGRESQL__PORT = toString config.services.postgresql.settings.port;
    AUTHENTIK_POSTGRESQL__NAME = "authentik";
    AUTHENTIK_POSTGRESQL__USER = serviceUser;
    AUTHENTIK_POSTGRESQL__SSLMODE = "disable";

    AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS = "127.0.0.0/8,::1/128";
    AUTHENTIK_STORAGE__FILE__PATH = cfg.paths.dataDir;
    AUTHENTIK_CERT_DISCOVERY_DIR = "${cfg.paths.dataDir}/certs";
    AUTHENTIK_SECRET_KEY = "file://${secretPath "authentik/secretKey"}";

    AUTHENTIK_DISABLE_UPDATE_CHECK = "true";
    AUTHENTIK_DISABLE_STARTUP_ANALYTICS = "true";
    AUTHENTIK_ERROR_REPORTING__ENABLED = "false";
    AUTHENTIK_LOG_LEVEL = "info";
  };

  mkAuthentikService = role: environment: {
    description = "authentik ${role}";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "authentik-database-setup.service"];
    wants = ["network-online.target"];
    requires = ["authentik-database-setup.service"];
    inherit environment;

    preStart = ''
      test -r ${lib.escapeShellArg (secretPath "authentik/secretKey")} \
        && test -s ${lib.escapeShellArg (secretPath "authentik/secretKey")} || {
        echo "Missing or unreadable authentik signing key; startup refused." >&2
        exit 1
      }
      ${config.services.postgresql.package}/bin/pg_isready \
        --host /run/postgresql \
        --port ${toString config.services.postgresql.settings.port} \
        --dbname authentik \
        --username ${serviceUser}
    '';

    unitConfig.RequiresMountsFor = [cfg.paths.dataDir];

    serviceConfig = {
      Type = "simple";
      User = serviceUser;
      Group = serviceGroup;
      WorkingDirectory = cfg.paths.dataDir;
      ExecStart = "${pkgs.authentik}/bin/ak ${role}";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
in {
  options.nixstead.services.authentik = serviceOptionFromRegistry "authentik" {
    pathOptions.dataDir = runtimePathOption "/var/lib/authentik" "Absolute directory containing authentik media and application state.";
    extraOptions = {
      workerPort = lib.mkOption {
        type = lib.types.port;
        default = serviceRegistry.authentik.defaults.workerPort;
        description = "Loopback HTTP port used by the authentik worker.";
      };
      metricsPort = lib.mkOption {
        type = lib.types.port;
        default = serviceRegistry.authentik.defaults.metricsPort;
        description = "Loopback Prometheus metrics port used by the authentik server.";
      };
      workerMetricsPort = lib.mkOption {
        type = lib.types.port;
        default = serviceRegistry.authentik.defaults.workerMetricsPort;
        description = "Loopback Prometheus metrics port used by the authentik worker.";
      };
      httpsPort = lib.mkOption {
        type = lib.types.port;
        default = serviceRegistry.authentik.defaults.httpsPort;
        description = "Loopback HTTPS port used by authentik's internal TLS listener.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."authentik/secretKey" = {
      owner = serviceUser;
      group = serviceGroup;
      mode = "0400";
      restartUnits = ["authentik-server.service" "authentik-worker.service"];
    };

    users.groups.${serviceGroup} = {};
    users.users.${serviceUser} = {
      isSystemUser = true;
      group = serviceGroup;
      home = cfg.paths.dataDir;
    };

    services.postgresql = {
      enable = true;
      authentication = lib.mkAfter ''
        local authentik authentik peer
      '';
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.paths.dataDir} 0750 ${serviceUser} ${serviceGroup} -"
      "d ${cfg.paths.dataDir}/certs 0750 ${serviceUser} ${serviceGroup} -"
    ];

    systemd.services = {
      authentik-database-setup = {
        description = "Create the authentik PostgreSQL role and database";
        after = ["postgresql-setup.service"];
        requires = ["postgresql-setup.service"];
        before = ["authentik-server.service" "authentik-worker.service"];

        script = ''
          ${config.services.postgresql.package}/bin/psql \
            --host /run/postgresql \
            --port ${toString config.services.postgresql.settings.port} \
            --dbname postgres \
            --set ON_ERROR_STOP=1 <<'SQL'
          SELECT 'CREATE ROLE authentik LOGIN'
            WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'authentik') \gexec
          SELECT 'CREATE DATABASE authentik OWNER authentik TEMPLATE template0'
            WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_database WHERE datname = 'authentik') \gexec
          ALTER DATABASE authentik OWNER TO authentik;
          SQL
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          Group = "postgres";
        };
      };

      authentik-server = mkAuthentikService "server" (
        commonEnvironment
        // {
          AUTHENTIK_LISTEN__HTTP = "${serviceBindAddress "authentik"}:${toString cfg.port}";
          AUTHENTIK_LISTEN__HTTPS = "127.0.0.1:${toString cfg.httpsPort}";
          AUTHENTIK_LISTEN__METRICS = "127.0.0.1:${toString cfg.metricsPort}";
        }
      );

      authentik-worker = mkAuthentikService "worker" (
        commonEnvironment
        // {
          AUTHENTIK_LISTEN__HTTP = "127.0.0.1:${toString cfg.workerPort}";
          AUTHENTIK_LISTEN__METRICS = "127.0.0.1:${toString cfg.workerMetricsPort}";
        }
      );
    };
  };
}
