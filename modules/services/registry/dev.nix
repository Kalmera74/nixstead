{
  mkService,
  localProxy,
  card,
  health,
  backup,
  setup,
  credential,
  ...
}: {
  grafana = mkService {
    name = "Grafana";
    optionPath = ["dev" "grafana"];
    defaults = {
      subdomain = "grafana";
      port = 3001;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "OTEL" 10 "Grafana" "grafana" "Dashboards")
      // {
        widget = {
          type = "grafana";
          extra.version = 2;
          secrets = {
            username = "grafanaUsername";
            password = "grafanaPassword";
          };
        };
      };
    health = (health "grafana.service") // {devDetailed = true;};
    secrets = ["devdb"];
    credentials = [
      (credential.sops "username" ["devdb" "grafana" "adminUser"])
      (credential.sops "password" ["devdb" "grafana" "adminPassword"])
    ];
    # The service is stopped before copying its SQLite database and mutable state.
    # The original encryption key is recovered from the encrypted SOPS source.
    backup =
      (backup "grafana" "grafana.service" "grafana" "grafana")
      // {
        nativePathOption = ["services" "grafana" "dataDir"];
        defaultPath = "/var/lib/grafana";
        requiredFiles = ["data/grafana.db"];
      };
    setup = setup "dev" 210 ["development" "full"];
  };

  prometheus = mkService {
    # Local metric history is disposable. Recollection after loss does not
    # recover earlier samples, so this policy intentionally has no backup.
    name = "Prometheus";
    optionPath = ["dev" "prometheus"];
    defaults = {
      subdomain = "prometheus";
      port = 9091;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "OTEL" 30 "Prometheus" "prometheus" "Metrics";
    health = (health "prometheus.service") // {devDetailed = true;};
    setup = setup "dev" 220 ["development" "full"];
  };

  loki = mkService {
    # Local log history is disposable. Producers may resume ingestion after
    # loss, but this policy does not promise replay or historical recovery.
    name = "Loki";
    optionPath = ["dev" "loki"];
    defaults = {
      subdomain = "loki";
      port = 3100;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "OTEL" 40 "Loki" "loki" "Logs";
    health = (health "loki.service") // {devDetailed = true;};
    setup = setup "dev" 230 ["development" "full"];
  };

  redis = mkService {
    name = "Redis";
    optionPath = ["dev" "redis"];
    defaults = {
      subdomain = "redis";
      port = 6379;
    };
    firewall = true;
    homepage = (card "Datastores" 10 "Redis" "redis" "Cache") // {hrefScheme = "tcp";};
    health =
      (health "redis.service")
      // {
        protocol = "tcp";
        devDetailed = true;
      };
    secrets = ["devdb"];
    credentials = [
      (credential.sops "username" ["devdb" "redis" "rootUser"])
      (credential.sops "password" ["devdb" "redis" "rootPassword"])
    ];
    # Stopping the native RDB writer flushes its selected dataset. ACL identity
    # is reconstructed from the encrypted source, outside this state snapshot.
    backup =
      (backup "redis" "redis.service" "redis" "redis")
      // {
        nativePathOption = ["services" "redis" "servers" "" "settings" "dir"];
        defaultPath = "/var/lib/redis";
        rdbServerOption = ["services" "redis" "servers" ""];
        rdbPackageOption = ["services" "redis" "package"];
      };
    setup = setup "dev" 240 ["development" "full"];
  };

  rabbitmq = mkService {
    name = "RabbitMQ";
    optionPath = ["dev" "rabbitmq"];
    defaults = {
      subdomain = "rabbitmq";
      port = 5672;
    };
    firewall = true;
    homepage = (card "Datastores" 20 "RabbitMQ" "rabbitmq" "Queue") // {hrefScheme = "tcp";};
    health =
      (health "rabbitmq.service")
      // {
        protocol = "tcp";
        devDetailed = true;
      };
    secrets = ["devdb"];
    credentials = [
      (credential.sops "username" ["devdb" "rabbitmq" "rootUser"])
      (credential.sops "password" ["devdb" "rabbitmq" "rootPassword"])
    ];
    # A stopped node snapshot includes definitions, durable messages and cookie.
    # Restore requires the original node name and the same supported revision.
    backup =
      (backup "rabbitmq" "rabbitmq.service" "rabbitmq" "rabbitmq")
      // {
        nativePathOption = ["services" "rabbitmq" "dataDir"];
        defaultPath = "/var/lib/rabbitmq";
        requiredFiles = [".erlang.cookie"];
      };
    setup = setup "dev" 250 ["development" "full"];
  };

  postgresql = mkService {
    name = "PostgreSQL";
    optionPath = ["dev" "postgresql"];
    defaults = {
      subdomain = "postgres";
      port = 5432;
    };
    firewall = true;
    homepage = (card "Datastores" 30 "PostgreSQL" "postgresql" "Database") // {hrefScheme = "tcp";};
    health =
      (health "postgresql.service")
      // {
        protocol = "tcp";
        devDetailed = true;
      };
    secrets = ["devdb"];
    credentials = [
      (credential.sops "username" ["devdb" "postgresql" "rootUser"])
      (credential.sops "password" ["devdb" "postgresql" "rootPassword"])
    ];
    backup =
      (backup "postgresql" "postgresql.service" "postgres" "postgres")
      // {
        nativePathOption = ["services" "postgresql" "dataDir"];
        defaultPath = "/var/lib/postgresql";
        database = "postgresql";
        databasePortOption = ["services" "postgresql" "settings" "port"];
        databaseUnit = "postgresql.service";
      };
    setup = setup "dev" 260 ["development" "full"];
  };

  mongodb = mkService {
    name = "MongoDB";
    optionPath = ["dev" "mongodb"];
    defaults = {
      subdomain = "mongo";
      port = 27017;
    };
    firewall = true;
    homepage = (card "Datastores" 40 "MongoDB" "mongodb" "Document DB") // {hrefScheme = "tcp";};
    health =
      (health "mongodb.service")
      // {
        protocol = "tcp";
        devDetailed = true;
      };
    secrets = ["devdb"];
    credentials = [
      (credential.literal "username" "root" "")
      (credential.sops "password" ["devdb" "mongodb" "rootPassword"])
    ];
    backup =
      (backup "mongodb" "mongodb.service" "mongodb" "mongodb")
      // {
        nativePathOption = ["services" "mongodb" "dbpath"];
        defaultPath = "/var/lib/mongodb";
        requiredFiles = ["storage.bson" "WiredTiger" "WiredTiger.wt" "WiredTiger.turtle"];
        mongodbPackageOption = ["services" "mongodb" "package"];
      };
    setup = setup "dev" 270 ["development" "full"];
  };

  forgejo = mkService {
    name = "Forgejo";
    optionPath = ["dev" "forgejo"];
    defaults = {
      subdomain = "forgejo";
      port = 3000;
    };
    firewall = true;
    proxy = localProxy // {websockets = true;};
    homepage = card "Dev Tools" 50 "Forgejo" "forgejo" "Git Forge";
    health = health "forgejo.service";
    secrets = ["forgejo"];
    credentials = [
      (credential.sops "username" ["forgejo" "initialAdmin" "username"])
      (credential.sops "email" ["forgejo" "initialAdmin" "email"])
      (credential.sops "password" ["forgejo" "initialAdmin" "password"])
    ];
    backup =
      (backup "forgejo" "forgejo.service" "forgejo" "forgejo")
      // {
        nativePathOption = ["services" "forgejo" "stateDir"];
        defaultPath = "/var/lib/forgejo";
        extraNativePathOptions = [["services" "forgejo" "repositoryRoot"]];
        ownerOption = ["services" "forgejo" "user"];
        groupOption = ["services" "forgejo" "group"];
        requiredFilesFromNativeSQLite = {
          typeOption = ["services" "forgejo" "database" "type"];
          pathOption = ["services" "forgejo" "database" "path"];
        };
      };
    setup =
      (setup "dev" 280 ["development" "full"])
      // {
        support = "x86_64 native SQLite startup, administrator readiness and clean marker Borg restore smoke passed; application workflows remain outside the maintained smoke";
      };
  };

  gitea = mkService {
    name = "Gitea";
    optionPath = ["dev" "gitea"];
    defaults = {
      subdomain = "gitea";
      port = 3002;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Dev Tools" 55 "Gitea" "gitea" "Git Forge")
      // {
        widget = {
          type = "gitea";
          secrets.key = "giteaApiToken";
        };
      };
    health = health "gitea.service";
    secrets = ["gitea"];
    credentials = [
      (credential.sops "username" ["gitea" "initialAdmin" "username"])
      (credential.sops "email" ["gitea" "initialAdmin" "email"])
      (credential.sops "password" ["gitea" "initialAdmin" "password"])
    ];
    backup =
      (backup "gitea" "gitea.service" "gitea" "gitea")
      // {
        nativePathOption = ["services" "gitea" "stateDir"];
        defaultPath = "/var/lib/gitea";
        extraNativePathOptions = [["services" "gitea" "repositoryRoot"]];
        ownerOption = ["services" "gitea" "user"];
        groupOption = ["services" "gitea" "group"];
        requiredFilesFromNativeSQLite = {
          typeOption = ["services" "gitea" "database" "type"];
          pathOption = ["services" "gitea" "database" "path"];
        };
      };
    setup =
      setup "dev" 290 []
      // {support = "x86_64 native SQLite startup, administrator readiness and clean marker Borg restore smoke passed; application workflows remain outside the maintained smoke";};
  };

  pgadmin = mkService {
    name = "pgAdmin";
    optionPath = ["dev" "pgadmin"];
    defaults = {
      subdomain = "pgadmin";
      port = 5050;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "Dev Tools" 20 "pgAdmin" "pgadmin" "PostgreSQL Admin";
    health = health "pgadmin.service";
    secrets = ["devdb"];
    credentials = [
      (credential.option "email" ["initialEmail"])
      (credential.sops "password" ["devdb" "pgadmin" "initialPassword"])
    ];
    # pgAdmin's own account/configuration SQLite state is distinct from managed DBs.
    backup =
      (backup "pgadmin" "pgadmin.service" "pgadmin" "pgadmin")
      // {
        dynamicUser = true;
        requiredFilesFromNativeSQLite.pathOption = ["services" "pgadmin" "settings" "SQLITE_PATH"];
      };
    setup = setup "dev" 300 ["development" "full"];
  };

  seaweedfs = mkService {
    name = "SeaweedFS";
    optionPath = ["dev" "seaweedfs"];
    defaults = {
      subdomain = "seaweed";
      port = 8888;
      masterPort = 9333;
    };
    firewall = true;
    listeners.settingsTcpPorts = ["port" "masterPort"];
    proxy = localProxy;
    homepage = card "Dev Tools" 60 "SeaweedFS" "filebrowser" "Object Storage";
    health = health "seaweedfs.service";
    # One process owns the local master, volume and embedded filer; stop it once
    # before archiving their common root so metadata and object bytes agree.
    backup =
      (backup "seaweedfs" "seaweedfs.service" "root" "root")
      // {
        # The configured leveldb2 backend owns eight metadata shards. Losing a
        # shard silently reconstructs an empty one, so refuse incomplete input.
        requiredFiles = map (shard: "filer/${shard}/CURRENT") ["00" "01" "02" "03" "04" "05" "06" "07"];
      };
    setup = setup "dev" 310 ["development" "full"];
  };

  uptimekuma = mkService {
    name = "Uptime Kuma";
    optionPath = ["dev" "uptimekuma"];
    defaults = {
      subdomain = "uptimekuma";
      port = 3010;
    };
    firewall = true;
    containerPublished = true;
    proxy = localProxy;
    homepage =
      (card "Infrastructure" 40 "Uptime Kuma" "uptime-kuma" "Service Monitoring")
      // {
        hrefSuffix = "/status/home";
        widget = {
          type = "uptimekuma";
          target = "loopback";
          extra.slug = "home";
        };
      };
    health = health "docker-uptimekuma.service";
    credentials = [
      (credential.manual "Create the first administrator in the Uptime Kuma web interface.")
    ];
    ociImages.application = {
      # renovate: datasource=docker depName=louislam/uptime-kuma
      default = "louislam/uptime-kuma:1.23.17@sha256:3d632903e6af34139a37f18055c4f1bfd9b7205ae1138f1e5e8940ddc1d176f9";
      repository = "louislam/uptime-kuma";
      role = "application";
    };
    backup = backup "uptimekuma" "docker-uptimekuma.service" "root" "root";
    setup = (setup "dev" 320 ["development" "full"]) // {suggestDocker = true;};
  };

  ntfy = mkService {
    name = "ntfy";
    optionPath = ["dev" "ntfy"];
    defaults = {
      subdomain = "ntfy";
      port = 2586;
    };
    firewall = true;
    proxy =
      localProxy
      // {
        websockets = true;
        extraLocationConfig = ''
          client_max_body_size 100m;
          proxy_request_buffering off;
        '';
      };
    homepage = card "Infrastructure" 50 "ntfy" "ntfy" "Push Notifications";
    health = health "ntfy-sh.service";
    credentials = [
      (credential.option "username" ["adminUsername"])
      (credential.file {
        label = "password";
        path = "/var/lib/ntfy-sh/admin-password";
        pathOption = ["adminPasswordFile"];
      })
    ];
    backup =
      (backup "ntfy-sh" "ntfy-sh.service" "root" "root")
      // {
        dynamicUser = true;
        requiredFiles = ["user.db" "cache.db"];
        requiredFilesWhenNull = [
          {
            option = ["adminPasswordFile"];
            files = ["admin-password"];
          }
        ];
      };
    setup = setup "dev" 330 ["development" "full"];
  };
}
