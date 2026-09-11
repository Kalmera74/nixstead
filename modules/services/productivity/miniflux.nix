{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity.miniflux;
  dataDir = cfg.paths.dataDir;
  databasePort = toString config.services.postgresql.settings.port;
  generateCredentials = cfg.adminCredentialsFile == null;
  credentialsFile =
    if generateCredentials
    then "${dataDir}/admin.env"
    else cfg.adminCredentialsFile;
  bootstrapCredentials = pkgs.writeShellScript "miniflux-bootstrap-credentials" ''
    set -euo pipefail

    install -d -m 0700 ${lib.escapeShellArg dataDir}
    if [ ! -s ${lib.escapeShellArg credentialsFile} ]; then
      umask 077
      {
        printf 'ADMIN_USERNAME=admin\n'
        printf 'ADMIN_PASSWORD='
        ${pkgs.openssl}/bin/openssl rand -hex 24
      } > ${lib.escapeShellArg "${credentialsFile}.tmp"}
      mv -f ${lib.escapeShellArg "${credentialsFile}.tmp"} ${lib.escapeShellArg credentialsFile}
    fi
  '';
in {
  config = lib.mkIf cfg.enable {
    services.miniflux = {
      enable = true;
      createDatabaseLocally = false;
      adminCredentialsFile = credentialsFile;
      config = {
        LISTEN_ADDR = "${serviceBindAddress "miniflux"}:${toString cfg.port}";
        BASE_URL = "https://${cfg.domain}/";
        DATABASE_URL = "user=miniflux host=/run/postgresql port=${databasePort} dbname=miniflux";
        CREATE_ADMIN = true;
        RUN_MIGRATIONS = true;
      };
    };

    services.postgresql = {
      enable = true;
      authentication = lib.mkAfter ''
        local miniflux miniflux peer
      '';
    };

    systemd.services = {
      miniflux-bootstrap-credentials = lib.mkIf generateCredentials {
        description = "Generate the Miniflux bootstrap administrator credential";
        before = ["miniflux.service"];
        unitConfig.RequiresMountsFor = [dataDir];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = bootstrapCredentials;
        };
      };

      miniflux-database-setup = {
        description = "Create the Miniflux PostgreSQL role and database";
        after = ["postgresql.service"];
        requires = ["postgresql.service"];
        before = ["miniflux.service"];

        script = ''
          ${config.services.postgresql.package}/bin/psql \
            --port ${databasePort} \
            --dbname postgres \
            --set ON_ERROR_STOP=1 <<'SQL'
          SELECT 'CREATE ROLE miniflux LOGIN'
            WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'miniflux') \gexec
          SELECT 'CREATE DATABASE miniflux OWNER miniflux TEMPLATE template0'
            WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_database WHERE datname = 'miniflux') \gexec
          ALTER DATABASE miniflux OWNER TO miniflux;
          SQL
        '';

        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          Group = "postgres";
        };
      };

      miniflux = {
        requires =
          lib.optional generateCredentials "miniflux-bootstrap-credentials.service"
          ++ ["miniflux-database-setup.service"];
        after =
          lib.optional generateCredentials "miniflux-bootstrap-credentials.service"
          ++ ["miniflux-database-setup.service"];
        unitConfig.RequiresMountsFor = [dataDir credentialsFile];
      };
    };
  };
}
