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
  paperless = mkService {
    name = "Paperless-ngx";
    optionPath = ["productivity" "paperless"];
    defaults = {
      subdomain = "paperless";
      port = 28981;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Productivity" 10 "Paperless" "paperless-ngx" "Documents")
      // {
        widget = {
          type = "paperlessngx";
          secrets.key = "paperlessApiKey";
        };
      };
    health = health "paperless-web.service";
    credentials = [
      (credential.manual "Create or reset an administrator with: sudo -u paperless paperless-manage createsuperuser")
    ];
    backup =
      (backup "paperless" "paperless-web.service" "paperless" "paperless")
      // {
        nativePathOption = ["services" "paperless" "dataDir"];
        defaultPath = "/var/lib/paperless";
        extraNativePathOptions = [["services" "paperless" "mediaDir"] ["services" "paperless" "consumptionDir"]];
        database = "postgresql";
        databasePortOption = ["services" "postgresql" "settings" "port"];
        databaseName = "paperless";
        databaseNameOption = ["services" "paperless" "settings" "PAPERLESS_DBNAME"];
        units = ["paperless-web.service" "paperless-consumer.service" "paperless-scheduler.service" "paperless-task-queue.service"];
        databaseUnit = "postgresql.service";
      };
    setup = (setup "productivity" 430 ["full"]) // {suggestDocker = true;};
  };

  nextcloud = mkService {
    name = "Nextcloud";
    optionPath = ["productivity" "nextcloud"];
    defaults = {
      subdomain = "nextcloud";
      port = 8083;
    };
    proxy = localProxy // {vhostKey = "nextcloud-proxy";};
    homepage =
      (card "Productivity" 20 "Nextcloud" "nextcloud" "Cloud Storage")
      // {
        widget = {
          type = "nextcloud";
          secrets.key = "nextcloudToken";
        };
      };
    health = health "phpfpm-nextcloud.service";
    credentials = [
      (credential.literal "username" "admin" "")
      (credential.file {
        label = "password";
        path = "/var/lib/nextcloud/nixos-nextcloud-admin-pass";
        pathOption = ["adminPasswordFile"];
      })
    ];
    backup =
      (backup "nextcloud" "phpfpm-nextcloud.service" "nextcloud" "nextcloud")
      // {
        nativePathOption = ["services" "nextcloud" "home"];
        defaultPath = "/var/lib/nextcloud";
        extraNativePathOptions = [["services" "nextcloud" "datadir"]];
        units = ["nextcloud-cron.timer" "nextcloud-cron.service" "phpfpm-nextcloud.service"];
      };
    setup =
      ((setup "productivity" 440 ["full"]) // {suggestDocker = true;})
      // {
        support = "x86_64 VM passed: first install and file restore";
        requirements = "Persistent files and SQLite state; PHP workers need memory; generated local admin password";
      };
  };

  n8n = mkService {
    name = "n8n";
    optionPath = ["productivity" "n8n"];
    defaults = {
      subdomain = "n8n";
      port = 5678;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "Productivity" 30 "n8n" "n8n" "Automation";
    health = health "n8n.service";
    credentials = [
      (credential.manual "Create the owner account in the n8n first-use web flow; n8n has no default login in this configuration.")
    ];
    backup =
      (backup "n8n" "n8n.service" "root" "root")
      // {
        dynamicUser = true;
        requiredFiles = [".n8n/config"];
        requiredJsonStrings = [
          {
            file = ".n8n/config";
            keys = ["encryptionKey"];
          }
        ];
        requiredFilesWhenNativeEquals = builtins.concatMap (databaseType:
          builtins.map (databasePath: {
            option = ["services" "n8n" "environment" "DB_TYPE"];
            value = databaseType;
            files = [".n8n/database.sqlite"];
            extraMatches = [
              {
                option = ["services" "n8n" "environment" "DB_SQLITE_DATABASE"];
                value = databasePath;
              }
              {
                option = ["services" "n8n" "environment" "DB_TYPE_FILE"];
                value = null;
              }
              {
                option = ["services" "n8n" "environment" "DB_SQLITE_DATABASE_FILE"];
                value = null;
              }
              {
                option = ["systemd" "services" "n8n" "serviceConfig" "EnvironmentFile"];
                value = null;
              }
            ];
          }) [null "database.sqlite"])
        [null "sqlite"];
      };
    setup = (setup "productivity" 450 ["full"]) // {suggestDocker = true;};
  };

  stirlingpdf = mkService {
    name = "Stirling PDF";
    optionPath = ["productivity" "stirlingpdf"];
    defaults = {
      subdomain = "pdf";
      port = 8082;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "Productivity" 40 "Stirling PDF" "stirling-pdf" "PDF Tools";
    health = health "stirling-pdf.service";
    setup = (setup "productivity" 460 ["full"]) // {suggestDocker = true;};
  };

  seafile = mkService {
    name = "Seafile";
    optionPath = ["productivity" "seafile"];
    defaults = {
      subdomain = "seafile";
      port = 8184;
    };
    firewall = true;
    containerPublished = true;
    proxy = localProxy;
    homepage = card "Productivity" 50 "Seafile" "seafile" "File Sync";
    health = health "docker-seafile.service";
    ociImages = {
      application = {
        # renovate: datasource=docker depName=seafileltd/seafile-mc
        default = "seafileltd/seafile-mc:11.0.13@sha256:1239b087aa4bdf1b60a3802e80855f230736ac5d5fa3325a40b15d4c598f422c";
        repository = "seafileltd/seafile-mc";
        role = "application";
      };
      database = {
        # renovate: datasource=docker depName=mariadb
        default = "mariadb:10.11.18@sha256:de61fed4a40d3842f3ee09944ba52792156cfd9adf489b2cc670fc6ded28df8d";
        repository = "mariadb";
        role = "database";
      };
      memcached = {
        # renovate: datasource=docker depName=memcached
        default = "memcached:1.6.45@sha256:eeb9eaa939ffaa2304899674c9e88a9247ec8e5e40e424a892df7b09914bd2ec";
        repository = "memcached";
        role = "cache";
      };
    };
    secrets = ["seafile"];
    credentials = [
      (credential.sops "email" ["seafile" "adminEmail"])
      (credential.sops "password" ["seafile" "adminPassword"])
    ];
    backup =
      (backup "seafile" "docker-seafile.service" "root" "root")
      // {
        nativePathOption = ["nixstead" "services" "productivity" "seafile" "paths" "dataDir"];
        nativePathSuffix = "/data";
        requiredFiles = ["seafile/conf/ccnet.conf" "seafile/conf/seafile.conf" "seafile/conf/seahub_settings.py"];
        requiredDirectories = ["seafile/seafile-data/storage/blocks" "seafile/seafile-data/storage/commits" "seafile/seafile-data/storage/fs"];
        units = ["docker-seafile.service" "docker-seafile-db.service" "docker-seafile-memcached.service"];
        database = "mariadb-container";
        databaseContainer = "seafile-db";
        databaseName = "seafile_db";
        databaseUnit = "docker-seafile-db.service";
        databaseNames = ["ccnet_db" "seafile_db" "seahub_db"];
      };
    setup =
      (setup "productivity" 470 ["full"])
      // {
        suggestDocker = true;
        support = "x86_64 startup and clean combined-state Borg restore smoke passed: all three databases, native configuration and file marker";
      };
  };

  wallabag = mkService {
    name = "Wallabag";
    optionPath = ["productivity" "wallabag"];
    defaults = {
      subdomain = "wallabag";
      port = 8185;
    };
    firewall = true;
    containerPublished = true;
    proxy = localProxy;
    homepage = card "Productivity" 60 "Wallabag" "wallabag" "Read Later";
    health = health "docker-wallabag.service";
    ociImages = {
      application = {
        # renovate: datasource=docker depName=wallabag/wallabag
        default = "wallabag/wallabag:2.6.14@sha256:4a527e027e0d59e87c14225ef11e005af3d4890374202ad319ce5e63dfc66709";
        repository = "wallabag/wallabag";
        role = "application";
      };
      database = {
        # renovate: datasource=docker depName=mariadb
        default = "mariadb:11.8.8@sha256:d9f7eb2637296652f24b484afd5d246f759f49f5babcadc6a9e344c9acb75fbf";
        repository = "mariadb";
        role = "database";
      };
      redis = {
        # renovate: datasource=docker depName=redis
        default = "redis:7.4.10-alpine@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2";
        repository = "redis";
        role = "cache";
      };
    };
    secrets = ["wallabag"];
    credentials = [
      (credential.literal "username" "wallabag" "Upstream bootstrap credential; change it immediately after first login.")
      (credential.literal "password" "wallabag" "Upstream bootstrap credential; change it immediately after first login.")
    ];
    backup =
      (backup "wallabag" "docker-wallabag.service" "root" "root")
      // {
        units = ["docker-wallabag.service" "docker-wallabag-db.service" "docker-wallabag-redis.service"];
        database = "mariadb-container";
        databaseContainer = "wallabag-db";
        databaseName = "wallabag";
        databaseUnit = "docker-wallabag-db.service";
      };
    setup = (setup "productivity" 480 ["full"]) // {suggestDocker = true;};
  };

  linkwarden = mkService {
    name = "Linkwarden";
    optionPath = ["productivity" "linkwarden"];
    defaults = {
      subdomain = "linkwarden";
      port = 8186;
    };
    firewall = true;
    containerPublished = true;
    proxy = localProxy;
    homepage =
      (card "Productivity" 70 "Linkwarden" "linkwarden" "Bookmark Manager")
      // {
        widget = {
          type = "linkwarden";
          secrets.key = "linkwardenApiKey";
        };
      };
    health = health "docker-linkwarden.service";
    ociImages = {
      application = {
        # renovate: datasource=docker depName=ghcr.io/linkwarden/linkwarden
        default = "ghcr.io/linkwarden/linkwarden:v2.16.0@sha256:d805877fb707d160b809027c302f84cfba11a248d7fdc12de90b4791f98e6b55";
        repository = "ghcr.io/linkwarden/linkwarden";
        role = "application";
      };
      database = {
        # renovate: datasource=docker depName=postgres
        default = "postgres:16.14-alpine@sha256:57c72fd2a128e416c7fcc499958864df5301e940bca0a56f58fddf30ffc07777";
        repository = "postgres";
        role = "database";
      };
      meilisearch = {
        # renovate: datasource=docker depName=getmeili/meilisearch
        default = "getmeili/meilisearch:v1.12.8@sha256:c9fac23131cca4db95173d41cc50fd5639121ee381795528fdd7522d7978a7b8";
        repository = "getmeili/meilisearch";
        role = "search";
      };
    };
    secrets = ["linkwarden"];
    credentials = [
      (credential.manual "Create the first Linkwarden account in the web interface; no login password is preseeded.")
    ];
    backup =
      (backup "linkwarden" "docker-linkwarden.service" "root" "root")
      // {
        units = ["docker-linkwarden.service" "docker-linkwarden-db.service" "docker-linkwarden-meilisearch.service"];
        database = "postgresql-container";
        databaseContainer = "linkwarden-db";
        databaseName = "linkwarden";
        databaseUnit = "docker-linkwarden-db.service";
      };
    setup = (setup "productivity" 490 ["full"]) // {suggestDocker = true;};
  };

  snapotter = mkService {
    name = "SnapOtter";
    optionPath = ["productivity" "snapotter"];
    defaults = {
      subdomain = "images";
      port = 8187;
    };
    firewall = true;
    containerPublished = true;
    proxy =
      localProxy
      // {
        websockets = true;
        extraLocationConfig = ''
          client_max_body_size 500m;
          proxy_request_buffering off;
          proxy_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    homepage = card "Productivity" 80 "SnapOtter" "mdi-image-edit-outline" "Image Tools";
    health = health "docker-snapotter.service";
    ociImages = {
      application = {
        # renovate: datasource=docker depName=snapotter/snapotter
        default = "snapotter/snapotter:2.2.0@sha256:2e11b4fa9138fa93e0fdfde5da3a2d042eebcfa81dd51286488872a3eb8086c8";
        repository = "snapotter/snapotter";
        role = "application";
      };
      database = {
        # renovate: datasource=docker depName=postgres
        default = "postgres:17-alpine@sha256:742f40ea20b9ff2ff31db5458d127452988a2164df9e17441e191f3b72252193";
        repository = "postgres";
        role = "database";
      };
      redis = {
        # renovate: datasource=docker depName=redis
        default = "redis:8-alpine@sha256:9d317178eceac8454a2284a9e6df2466b93c745529947f0cd42a0fa9609d7005";
        repository = "redis";
        role = "cache";
      };
    };
    secrets = ["snapotter"];
    credentials = [
      (credential.literal "username" "admin" "")
      (credential.sops "password" ["snapotter" "defaultPassword"])
    ];
    backup =
      (backup "snapotter" "docker-snapotter.service" "root" "root")
      // {
        units = [
          "docker-snapotter.service"
          "docker-snapotter-db.service"
          "docker-snapotter-redis.service"
        ];
        database = "postgresql-container";
        databaseContainer = "snapotter-db";
        databaseName = "snapotter";
        databaseUnit = "docker-snapotter-db.service";
      };
    setup = (setup "productivity" 500 ["full"]) // {suggestDocker = true;};
  };

  mealie = mkService {
    name = "Mealie";
    optionPath = ["productivity" "mealie"];
    defaults = {
      subdomain = "mealie";
      port = 8188;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "Productivity" 90 "Mealie" "mealie" "Recipes & Meal Planning";
    health = health "mealie.service";
    credentials = [
      (credential.literal "email" "changeme@example.com" "Upstream bootstrap credential; change it immediately after first login.")
      (credential.literal "password" "MyPassword" "Upstream bootstrap credential; change it immediately after first login.")
    ];
    backup =
      (backup "mealie" "mealie.service" "root" "root")
      // {
        dynamicUser = true;
        requiredFiles = ["mealie.db" ".secret" ".session_secret"];
      };
    setup = setup "productivity" 501 ["full"];
  };

  actualbudget = mkService {
    name = "Actual Budget";
    optionPath = ["productivity" "actualbudget"];
    defaults = {
      subdomain = "budget";
      port = 8189;
    };
    firewall = true;
    proxy = localProxy // {websockets = true;};
    homepage = card "Productivity" 100 "Actual Budget" "actual-budget" "Personal Finance";
    health = health "actual.service";
    credentials = [
      (credential.manual "Set the server password in Actual Budget's first-run web interface.")
    ];
    backup =
      (backup "actual" "actual.service" "root" "root")
      // {
        nativePathOption = ["services" "actual" "settings" "dataDir"];
        extraNativePathOptions = [
          ["services" "actual" "settings" "serverFiles"]
          ["services" "actual" "settings" "userFiles"]
        ];
        ownerOption = ["services" "actual" "user"];
        groupOption = ["services" "actual" "group"];
        requiredFiles = [".migrate"];
        requiredJsonFiles = [".migrate"];
        requiredFilesFromNativeSQLite = {
          pathOption = ["services" "actual" "settings" "serverFiles"];
          pathSuffix = "/account.sqlite";
        };
      };
    setup =
      (setup "productivity" 502 ["full"])
      // {
        support = "x86_64 startup and clean Borg restore smoke passed for default DynamicUser and custom named-account storage profiles";
      };
  };

  miniflux = mkService {
    name = "Miniflux";
    optionPath = ["productivity" "miniflux"];
    defaults = {
      subdomain = "reader";
      port = 8190;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "Productivity" 110 "Miniflux" "miniflux" "RSS Reader";
    health = health "miniflux.service";
    credentials = [
      (credential.file {
        label = "username";
        path = "/var/lib/miniflux/admin.env";
        pathOption = ["adminCredentialsFile"];
        envKey = "ADMIN_USERNAME";
      })
      (credential.file {
        label = "password";
        path = "/var/lib/miniflux/admin.env";
        pathOption = ["adminCredentialsFile"];
        envKey = "ADMIN_PASSWORD";
      })
    ];
    backup =
      (backup "miniflux" "miniflux.service" "root" "root")
      // {
        database = "postgresql";
        databasePortOption = ["services" "postgresql" "settings" "port"];
        databaseName = "miniflux";
        databaseUnit = "postgresql.service";
      };
    setup = setup "productivity" 503 ["full"];
  };

  searxng = mkService {
    name = "SearXNG";
    optionPath = ["productivity" "searxng"];
    defaults = {
      subdomain = "search";
      port = 8191;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "Productivity" 120 "SearXNG" "searxng" "Private Search";
    health = health "searx.service";
    backup =
      (backup "searxng" "searx.service" "root" "root")
      // {requiredFiles = ["environment"];};
    setup = setup "productivity" 504 ["full"];
  };
}
