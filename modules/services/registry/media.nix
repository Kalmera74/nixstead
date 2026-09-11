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
  jellyfin = mkService {
    name = "Jellyfin";
    optionPath = ["media" "jellyfin"];
    defaults = {
      subdomain = "watch";
      port = 8096;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Media" 10 "Jellyfin" "jellyfin" "Streaming")
      // {
        widget = {
          type = "jellyfin";
          secrets.key = "jellyfinApiKey";
        };
      };
    health = health "jellyfin.service";
    credentials = [
      (credential.manual "Create the first administrator in the Jellyfin web setup wizard.")
    ];
    backup =
      (backup "jellyfin" "jellyfin.service" "jellyfin" "jellyfin")
      // {
        nativePathOption = ["services" "jellyfin" "dataDir"];
        extraNativePathOptions = [["services" "jellyfin" "configDir"]];
        defaultPath = "/var/lib/jellyfin";
        ownerOption = ["services" "jellyfin" "user"];
        groupOption = ["services" "jellyfin" "group"];
        requiredFiles = ["data/jellyfin.db"];
      };
    setup =
      (setup "media-core" 110 ["media-starter" "media-server" "full"])
      // {
        support = "Verified x86_64 native startup and one clean application/configuration Borg restore with independent markers; earlier application-flow evidence is historical";
        requirements = "Persistent media library plus local metadata (Jellyfin requires 2 GiB free for data at startup); transcoding may require a GPU";
      };
  };

  seerr = mkService {
    name = "Seerr";
    optionPath = ["media" "seerr"];
    defaults = {
      subdomain = "want";
      port = 5055;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Media" 20 "Seerr" "seerr" "Requests")
      // {
        widget = {
          type = "seerr";
          secrets.key = "seerrApiKey";
        };
      };
    api = {
      sopsSecret = "seerr/apiKey";
      previousSecrets = ["homepage/seerrApiKey"];
      format = "seerr";
      nativePathOption = ["services" "seerr" "configDir"];
      suffix = "settings.json";
    };
    health = health "seerr.service";
    credentials = [
      (credential.manual "Complete Seerr onboarding with an existing Jellyfin administrator account.")
    ];
    backup =
      (backup "seerr" "seerr.service" "root" "root")
      // {
        nativePathOption = ["services" "seerr" "configDir"];
        defaultPath = "/var/lib/seerr";
        dynamicUser = true;
        requiredFiles = ["settings.json" "db/db.sqlite3"];
        requiredJsonFiles = ["settings.json"];
        requiredSQLiteFiles = ["db/db.sqlite3"];
      };
    setup =
      (setup "media-core" 120 ["media-starter" "media-server" "full"])
      // {
        support = "x86_64 native startup and clean canonical state-marker Borg restore smoke passed; account/request workflows are outside the maintained smoke";
        requirements = "Local SQLite state; Jellyfin administrator needed for onboarding";
      };
  };

  tdarr = mkService {
    name = "Tdarr";
    optionPath = ["media" "tdarr"];
    enablePath = ["media" "tdarr" "server"];
    defaults = {
      subdomain = "tdarr";
      port = 8265;
      serverPort = 8266;
    };
    firewall = {
      primary = true;
      settingsTcpPorts = ["serverPort"];
    };
    listeners.settingsTcpPorts = ["port" "serverPort"];
    proxy = localProxy // {websockets = true;};
    homepage =
      (card "Media" 30 "Tdarr" "tdarr" "Transcoding")
      // {
        widget.type = "tdarr";
      };
    health = health "tdarr-server.service";
    backup =
      (backup "tdarr" "tdarr-server.service" "tdarr" "media")
      // {
        nativePathOption = ["services" "tdarr" "dataDir"];
        nativePathSuffix = "/server";
        defaultPath = "/var/lib/tdarr";
        ownerOption = ["services" "tdarr" "user"];
        groupOption = ["services" "tdarr" "group"];
        requiredFiles = ["configs/Tdarr_Server_Config.json"];
      };
    setup =
      ((setup "media-core" 130 ["media-server" "full"])
        // {optionPath = ["media" "tdarr" "enable"];})
      // {
        support = "x86_64 native server/node startup and clean server-state Borg marker restore smoke passed; transcodes and source media are outside scope";
        requirements = "Transcoding CPU or GPU capacity plus temporary output space as large as the media being processed";
      };
  };

  tdarr-node = mkService {
    name = "Tdarr node";
    optionPath = ["media" "tdarr"];
    enablePath = ["media" "tdarr" "node"];
    health = (health "tdarr-node-local.service") // {protocol = "none";};
  };

  komga = mkService {
    name = "Komga";
    optionPath = ["media" "komga"];
    defaults = {
      subdomain = "komga";
      port = 25600;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Media" 35 "Komga" "komga" "Comics & Manga")
      // {
        widget = {
          type = "komga";
          secrets = {
            username = "komgaUsername";
            password = "komgaPassword";
          };
        };
      };
    health = health "komga.service";
    credentials = [
      (credential.manual "Create the first administrator in the Komga web interface.")
    ];
    backup =
      (backup "komga" "komga.service" "komga" "komga")
      // {
        requiredFiles = ["database.sqlite"];
        requiredSQLiteFiles = ["database.sqlite"];
      };
    setup = (setup "media-extra" 140 ["media-server" "full"]) // {requirements = "Persistent comics library and application database; Java heap and thumbnail storage grow with catalog size";};
  };

  kavita = mkService {
    name = "Kavita";
    optionPath = ["media" "kavita"];
    defaults = {
      subdomain = "kavita";
      port = 5000;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Media" 40 "Kavita" "kavita" "Comics & eBooks")
      // {
        widget = {
          type = "kavita";
          secrets.key = "kavitaApiKey";
        };
      };
    health = health "kavita.service";
    credentials = [
      (credential.manual "Create the first administrator in the Kavita web setup wizard.")
    ];
    backup =
      (backup "kavita" "kavita.service" "kavita" "kavita")
      // {
        nativePathOption = ["services" "kavita" "dataDir"];
        defaultPath = "/var/lib/kavita";
        ownerOption = ["services" "kavita" "user"];
        groupOption = ["services" "kavita" "user"];
      };
    setup =
      (setup "media-extra" 150 ["media-server" "full"])
      // {
        support = "x86_64 native startup and clean Borg application-state restore smoke passed; source libraries are separately owned";
        requirements = "Persistent book library, database and cover cache; scanning adds CPU and memory load";
      };
  };

  audiobookshelf = mkService {
    name = "Audiobookshelf";
    optionPath = ["media" "audiobookshelf"];
    defaults = {
      subdomain = "audiobookshelf";
      port = 13378;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Media" 50 "Audiobookshelf" "audiobookshelf" "Audiobooks")
      // {
        widget = {
          type = "audiobookshelf";
          secrets.key = "audiobookshelfApiKey";
        };
      };
    health = health "audiobookshelf.service";
    credentials = [
      (credential.manual "Create the first administrator in the Audiobookshelf web setup flow.")
    ];
    backup =
      (backup "audiobookshelf" "audiobookshelf.service" "audiobookshelf" "audiobookshelf")
      // {
        nativePathOption = ["systemd" "services" "audiobookshelf" "serviceConfig" "WorkingDirectory"];
        defaultPath = "/var/lib/audiobookshelf";
        ownerOption = ["services" "audiobookshelf" "user"];
        groupOption = ["services" "audiobookshelf" "group"];
      };
    setup =
      (setup "media-extra" 160 ["media-server" "full"])
      // {
        requirements = "Persistent audiobook/podcast library plus metadata; reserve space for downloads and covers";
        support = "x86_64 native startup and clean application-state Borg restore smoke passed; source libraries remain separately owned";
      };
  };

  kiwix = mkService {
    name = "Kiwix";
    optionPath = ["media" "kiwix"];
    defaults = {
      subdomain = "wiki";
      port = 9090;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "Media" 60 "Wiki" "wiki" "Docs";
    health = health "kiwix-serve.service";
    setup = (setup "media-extra" 170 ["media-server" "full"]) // {requirements = "Download ZIM archives separately; archive sizes determine disk capacity; no content is bundled";};
  };

  immich = mkService {
    name = "Immich";
    optionPath = ["media" "immich"];
    defaults = {
      subdomain = "immich";
      port = 2283;
    };
    firewall = true;
    proxy =
      localProxy
      // {
        websockets = true;
        extraVhostConfig = "client_max_body_size 0;\n";
      };
    homepage =
      (card "Media" 70 "Immich" "immich" "Photos")
      // {
        widget = {
          type = "immich";
          secrets.key = "immichApiKey";
          extra.version = 2;
        };
      };
    health = health "immich-server.service";
    credentials = [
      (credential.manual "Create the first administrator in the Immich web interface.")
    ];
    backup =
      (backup "immich" "immich-server.service" "immich" "media")
      // {
        pathOption = ["paths" "mediaLocation"];
        nativePathOption = ["services" "immich" "mediaLocation"];
        defaultPath = "/var/lib/immich";
        ownerOption = ["services" "immich" "user"];
        groupOption = ["services" "immich" "group"];
        units = ["immich-server.service" "immich-machine-learning.service"];
        database = "postgresql";
        databasePortOption = ["services" "postgresql" "settings" "port"];
        databaseName = "immich";
        databaseFormat = "custom";
        databaseNameOption = ["services" "immich" "database" "name"];
        databaseUnit = "postgresql.service";
      };
    setup =
      (setup "media-extra" 180 ["media-server" "full"])
      // {
        support = "x86_64 native startup and clean PostgreSQL/media Borg marker restore smoke passed; earlier application-flow evidence is historical";
        requirements = "Photo originals, thumbnails and PostgreSQL on persistent storage; machine learning adds RAM and CPU use";
      };
  };

  romm = mkService {
    name = "RomM";
    optionPath = ["media" "romm"];
    defaults = {
      subdomain = "romm";
      port = 8182;
    };
    firewall = true;
    containerPublished = true;
    proxy = localProxy // {websockets = true;};
    homepage =
      (card "Media" 80 "RomM" "retrom" "ROM Manager")
      // {
        widget.type = "romm";
      };
    health = health "docker-romm.service";
    ociImages = {
      application = {
        # renovate: datasource=docker depName=ghcr.io/rommapp/romm
        default = "ghcr.io/rommapp/romm:5.2.0@sha256:3512f2ca455782f90247271bed23116e6bc675bc74e379be2c41696e607ab11e";
        repository = "ghcr.io/rommapp/romm";
        role = "application";
      };
      database = {
        # renovate: datasource=docker depName=mariadb
        default = "mariadb:11.3.2@sha256:e101f9db31916a5d4d7d594dd0dd092fb23ab4f499f1d7a7425d1afd4162c4bc";
        repository = "mariadb";
        role = "database";
      };
    };
    secrets = ["romm"];
    credentials = [
      (credential.manual "Create the first RomM user in the web interface.")
    ];
    backup =
      (backup "romm" "docker-romm.service" "root" "root")
      // {
        ownerOption = ["nixstead" "host" "user" "name"];
        ownerFallbackOption = ["nixstead" "host" "user" "uid"];
        groupOption = ["nixstead" "host" "groups" "media"];
        units = ["docker-romm.service" "docker-romm-db.service"];
        database = "mariadb-container";
        databaseContainer = "romm-db";
        databaseName = "romm";
        databaseUnit = "docker-romm-db.service";
        extraPathOptions = [["paths" "libraryDir"]];
      };
    setup =
      ((setup "media-extra" 190 ["media-server" "full"]) // {suggestDocker = true;})
      // {
        support = "x86_64 pinned application startup and clean MariaDB/application/library Borg marker restore smoke passed; populated ROM workflows are unverified";
        requirements = "ROM library, application state and MariaDB dump; container memory limits total 6 GiB";
      };
  };

  tubearchivist = mkService {
    name = "TubeArchivist";
    optionPath = ["media" "tubearchivist"];
    defaults = {
      subdomain = "tube";
      port = 8183;
    };
    firewall = true;
    containerPublished = true;
    proxy = localProxy;
    homepage =
      (card "Media" 90 "TubeArchivist" "youtube" "YouTube Archive")
      // {
        widget = {
          type = "tubearchivist";
          secrets.key = "tubearchivistApiKey";
        };
      };
    health = health "docker-tubearchivist.service";
    ociImages = {
      application = {
        # renovate: datasource=docker depName=bbilly1/tubearchivist
        default = "bbilly1/tubearchivist:v0.5.10@sha256:dfe723cf008520e1758ecc3e59e6ea8761dd10d5bb099cd87289e80f5bd66567";
        repository = "bbilly1/tubearchivist";
        role = "application";
      };
      elasticsearch = {
        # renovate: datasource=docker depName=bbilly1/tubearchivist-es
        default = "bbilly1/tubearchivist-es:8.19.0@sha256:9da63fb1973ec3d57daf6916be948eddd0d8a404cc8e447c938480c85fe2c554";
        repository = "bbilly1/tubearchivist-es";
        role = "search";
      };
      redis = {
        # renovate: datasource=docker depName=redis
        default = "redis:7.4.10-alpine@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2";
        repository = "redis";
        role = "cache";
      };
    };
    secrets = ["tubearchivist"];
    credentials = [
      (credential.sops "Username" ["tubearchivist" "username"])
      (credential.sops "Password" ["tubearchivist" "password"])
    ];
    backup =
      (backup "tubearchivist" "docker-tubearchivist.service" "root" "root")
      // {
        ownerOption = ["nixstead" "host" "user" "name"];
        ownerFallbackOption = ["nixstead" "host" "user" "uid"];
        groupOption = ["nixstead" "host" "groups" "media"];
        units = [
          "docker-tubearchivist.service"
          "docker-tubearchivist-es.service"
          "docker-tubearchivist-redis.service"
        ];
        extraPathOptions = [["paths" "mediaDir"]];
        database = "elasticsearch-container";
        databaseContainer = "tubearchivist-es";
        databaseName = "ta_*";
        databaseUnit = "docker-tubearchivist-es.service";
      };
    setup =
      ((setup "media-extra" 200 ["media-server" "full"]) // {suggestDocker = true;})
      // {
        support = "x86_64 pinned application startup and clean Elasticsearch/filesystem Borg restore smoke passed; populated workflows and active queues are unverified";
        requirements = "Video archive plus Elasticsearch and Redis state; container memory limits total 4.5 GiB";
      };
  };
}
