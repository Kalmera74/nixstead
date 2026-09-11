{
  config,
  host,
  lib,
  secretPlaceholder,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
in {
  config = lib.mkIf cfg.postgresql.enable {
    sops.secrets = {
      "devdb/postgresql/rootUser" = {};
      "devdb/postgresql/rootPassword" = {};
    };

    sops.templates."postgresql-admin.env" = {
      owner = "postgres";
      content = ''
        POSTGRES_ROOT_USER=${secretPlaceholder "devdb/postgresql/rootUser"}
        POSTGRES_ROOT_PASSWORD=${secretPlaceholder "devdb/postgresql/rootPassword"}
      '';
      restartUnits = ["postgresql.service"];
    };

    services.postgresql = {
      enable = true;
      settings = {
        port = config.nixstead.services.dev.postgresql.port;
        listen_addresses = lib.mkForce (serviceBindAddress "postgresql");
      };
    };

    systemd.services.postgresql.serviceConfig.EnvironmentFile = [config.sops.templates."postgresql-admin.env".path];
    systemd.services.postgresql.postStart = lib.mkAfter ''
      if [ -n "$POSTGRES_ROOT_USER" ] && [ -n "$POSTGRES_ROOT_PASSWORD" ]; then
        ${config.services.postgresql.package}/bin/psql --port ${toString config.services.postgresql.settings.port} --dbname postgres <<'SQL'
      \getenv root_user POSTGRES_ROOT_USER
      \getenv root_password POSTGRES_ROOT_PASSWORD
      SELECT format('CREATE ROLE %I WITH LOGIN SUPERUSER PASSWORD %L', :'root_user', :'root_password')
        WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = :'root_user') \gexec
      SELECT format('ALTER ROLE %I WITH LOGIN SUPERUSER PASSWORD %L', :'root_user', :'root_password')
        WHERE EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = :'root_user') \gexec
      SQL
      fi
    '';
  };
}
