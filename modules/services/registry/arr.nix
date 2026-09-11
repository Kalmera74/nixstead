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
  arr-integrations = mkService {
    name = "ARR relationship ownership";
    optionPath = ["arr" "integrations"];
    enablePath = ["arr" "integrations" "active"];
    health = (health "nixstead-arr-reconcile.timer") // {protocol = "none";};
    backup =
      (backup "nixstead-arr-integrations" "nixstead-arr-reconcile.service" "nixstead-arr-reconcile" "nixstead-arr-reconcile")
      // {
        units = ["nixstead-arr-reconcile.timer" "nixstead-arr-reconcile.service"];
        requiredFiles = ["ownership.json"];
      };
  };
  radarr = mkService {
    name = "Radarr";
    optionPath = ["arr" "radarr"];
    defaults = {
      subdomain = "radarr";
      port = 7878;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Arr" 10 "Radarr" "radarr" "Movies")
      // {
        widget = {
          type = "radarr";
          secrets.key = "radarrApiKey";
        };
      };
    api = {
      sopsSecret = "radarr/apiKey";
      previousSecrets = ["homepage/radarrApiKey" "swaparr/radarrApiKey"];
      format = "xml";
      nativePathOption = ["services" "radarr" "dataDir"];
      downloadClient = {
        relationship = "qbittorrentToRadarr";
        library = "movies";
      };
      suffix = "config.xml";
    };
    metrics = {
      exporter = "exportarr-radarr";
      port = 9708;
      credential = "radarr";
      scrapeInterval = "60s";
    };
    health = health "radarr.service";
    backup =
      (backup "radarr" "radarr.service" "radarr" "radarr")
      // {
        ownerOption = ["services" "radarr" "user"];
        groupOption = ["services" "radarr" "group"];
      };
    setup =
      (setup "arr" 20 ["media-starter" "media-server" "full"])
      // {
        support = "Application API coverage; restore unverified";
        requirements = "Persistent metadata plus movie and download roots; shared filesystem needed for hardlinks";
      };
  };

  sonarr = mkService {
    name = "Sonarr";
    optionPath = ["arr" "sonarr"];
    defaults = {
      subdomain = "sonarr";
      port = 8989;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Arr" 20 "Sonarr" "sonarr" "TV")
      // {
        widget = {
          type = "sonarr";
          secrets.key = "sonarrApiKey";
        };
      };
    api = {
      sopsSecret = "sonarr/apiKey";
      previousSecrets = ["homepage/sonarrApiKey" "swaparr/sonarrApiKey"];
      format = "xml";
      nativePathOption = ["services" "sonarr" "dataDir"];
      downloadClient = {
        relationship = "qbittorrentToSonarr";
        library = "tv";
      };
      suffix = "config.xml";
    };
    metrics = {
      exporter = "exportarr-sonarr";
      port = 9707;
      credential = "sonarr";
      scrapeInterval = "60s";
    };
    health = health "sonarr.service";
    backup =
      (backup "sonarr" "sonarr.service" "sonarr" "sonarr")
      // {
        # Preserve the established parent archive layout around native NzbDrone.
        ownerOption = ["services" "sonarr" "user"];
        groupOption = ["services" "sonarr" "group"];
      };
    setup =
      (setup "arr" 10 ["media-starter" "media-server" "full"])
      // {
        support = "VM startup and API coverage; restore unverified";
        requirements = "Persistent metadata plus TV and download roots; shared filesystem needed for hardlinks";
      };
  };

  lidarr = mkService {
    name = "Lidarr";
    optionPath = ["arr" "lidarr"];
    defaults = {
      subdomain = "lidarr";
      port = 8686;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Arr" 30 "Lidarr" "lidarr" "Music")
      // {
        widget = {
          type = "lidarr";
          secrets.key = "lidarrApiKey";
        };
      };
    api = {
      sopsSecret = "lidarr/apiKey";
      previousSecrets = ["homepage/lidarrApiKey" "swaparr/lidarrApiKey"];
      format = "xml";
      nativePathOption = ["services" "lidarr" "dataDir"];
      downloadClient = {
        relationship = "qbittorrentToLidarr";
        library = "music";
      };
      suffix = "config.xml";
    };
    metrics = {
      exporter = "exportarr-lidarr";
      port = 9709;
      credential = "lidarr";
      scrapeInterval = "60s";
    };
    health = health "lidarr.service";
    backup =
      (backup "lidarr" "lidarr.service" "lidarr" "lidarr")
      // {
        ownerOption = ["services" "lidarr" "user"];
        groupOption = ["services" "lidarr" "group"];
      };
    setup = setup "arr" 30 ["media-server" "full"];
  };

  readarr = mkService {
    name = "Readarr";
    optionPath = ["arr" "readarr"];
    defaults = {
      subdomain = "readarr";
      port = 8787;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Arr" 40 "Readarr" "readarr" "Books")
      // {
        widget = {
          type = "readarr";
          secrets.key = "readarrApiKey";
        };
      };
    health = health "readarr.service";
    backup =
      (backup "readarr" "readarr.service" "readarr" "readarr")
      // {
        nativePathOption = ["services" "readarr" "dataDir"];
        defaultPath = "/var/lib/readarr";
        ownerOption = ["services" "readarr" "user"];
        groupOption = ["services" "readarr" "group"];
      };
    setup = setup "arr" 40 [];
  };

  bazarr = mkService {
    name = "Bazarr";
    optionPath = ["arr" "bazarr"];
    defaults = {
      subdomain = "bazarr";
      port = 6767;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Arr" 50 "Bazarr" "bazarr" "Subtitles")
      // {
        widget = {
          type = "bazarr";
          secrets.key = "bazarrApiKey";
        };
      };
    api = {
      sopsSecret = "bazarr/apiKey";
      previousSecrets = ["homepage/bazarrApiKey"];
      format = "yaml";
      nativePathOption = ["services" "bazarr" "dataDir"];
      suffix = "config/config.yaml";
    };
    metrics = {
      exporter = "exportarr-bazarr";
      port = 9711;
      credential = "bazarr";
      scrapeInterval = "60s";
    };
    health = health "bazarr.service";
    backup =
      (backup "bazarr" "bazarr.service" "bazarr" "bazarr")
      // {
        nativePathOption = ["services" "bazarr" "dataDir"];
        defaultPath = "/var/lib/bazarr";
        ownerOption = ["services" "bazarr" "user"];
        groupOption = ["services" "bazarr" "group"];
      };
    setup = setup "arr" 50 ["media-server" "full"];
  };

  prowlarr = mkService {
    name = "Prowlarr";
    optionPath = ["arr" "prowlarr"];
    defaults = {
      subdomain = "prowlarr";
      port = 9696;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Arr" 60 "Prowlarr" "prowlarr" "Indexers")
      // {
        widget = {
          type = "prowlarr";
          secrets.key = "prowlarrApiKey";
        };
      };
    api = {
      sopsSecret = "prowlarr/apiKey";
      previousSecrets = ["homepage/prowlarrApiKey"];
      format = "xml";
      nativePathOption = ["services" "prowlarr" "dataDir"];
      suffix = "config.xml";
    };
    metrics = {
      exporter = "exportarr-prowlarr";
      port = 9710;
      credential = "prowlarr";
      scrapeInterval = "60s";
    };
    health = health "prowlarr.service";
    backup =
      (backup "prowlarr" "prowlarr.service" "root" "root")
      // {
        nativePathOption = ["services" "prowlarr" "dataDir"];
        defaultPath = "/var/lib/prowlarr";
      };
    setup =
      (setup "arr" 60 ["media-starter" "media-server" "full"])
      // {
        support = "Application API coverage; restore unverified";
        requirements = "Persistent indexer configuration; external indexer accounts are separate";
      };
  };

  qbittorrent = mkService {
    name = "qBittorrent";
    optionPath = ["arr" "qbittorrent"];
    defaults = {
      subdomain = "bit";
      port = 8080;
    };
    firewall = true;
    proxy = localProxy // {extraLocationConfig = "proxy_redirect off;\n";};
    homepage =
      (card "Arr" 70 "qBittorrent" "qbittorrent" "Downloads")
      // {
        widget = {
          type = "qbittorrent";
          secrets = {
            username = "qbittorrentUsername";
            password = "qbittorrentPassword";
          };
        };
      };
    health = health "qbittorrent.service";
    secrets = ["qbittorrent"];
    credentials = [
      (credential.sops "username" ["qbittorrent" "username"])
      (credential.sops "password" ["qbittorrent" "password"])
    ];
    backup =
      (backup "qBittorrent" "qbittorrent.service" "qbittorrent" "media")
      // {
        nativePathOption = ["services" "qbittorrent" "profileDir"];
        defaultPath = "/var/lib/qBittorrent";
        ownerOption = ["services" "qbittorrent" "user"];
        groupOption = ["services" "qbittorrent" "group"];
      };
    setup =
      (setup "arr" 70 ["media-starter" "media-server" "full"])
      // {
        support = "VM startup and API coverage; restore unverified";
        requirements = "Download storage; review upload limits and opt into a VPN if needed";
      };
  };

  sabnzbd = mkService {
    name = "SABnzbd";
    optionPath = ["arr" "sabnzbd"];
    defaults = {
      subdomain = "sab";
      port = 8085;
    };
    firewall = true;
    proxy = localProxy;
    homepage =
      (card "Arr" 75 "SABnzbd" "sabnzbd" "Usenet downloads")
      // {
        widget = {
          type = "sabnzbd";
          secrets.key = "sabnzbdApiKey";
        };
      };
    api = {
      sopsSecret = "sabnzbd/apiKey";
      previousSecrets = ["homepage/sabnzbdApiKey"];
      format = "ini";
      nativePathOption = ["nixstead" "services" "arr" "sabnzbd" "paths" "dataDir"];
      suffix = "sabnzbd.ini";
    };
    metrics = {
      exporter = "sabnzbd";
      port = 9712;
      credential = "sabnzbd";
      scrapeInterval = "60s";
    };
    health = health "sabnzbd.service";
    backup =
      (backup "sabnzbd" "sabnzbd.service" "sabnzbd" "media")
      // {
        groupOption = ["services" "sabnzbd" "group"];
        requiredFiles = ["sabnzbd.ini"];
      };
    setup = setup "arr" 90 [];
  };
  shelfmark = mkService {
    name = "Shelfmark";
    optionPath = ["arr" "shelfmark"];
    defaults = {
      subdomain = "shelfmark";
      port = 8084;
    };
    firewall = true;
    proxy = localProxy;
    homepage = card "Arr" 85 "Shelfmark" "shelfmark" "Book search and acquisition";
    health = health "shelfmark.service";
    backup = (backup "shelfmark" "shelfmark.service" "root" "root") // {dynamicUser = true;};
    setup =
      (setup "arr" 95 [])
      // {
        inputs = [
          {
            optionPath = ["arr" "shelfmark" "paths" "ingestDir"];
            kind = "path";
            label = "Shelfmark ingest directory";
            help = "Explicit absolute ingest path. Prepare permissions or enable ARR directory management; paths under /mnt require a declared mount.";
          }
        ];
      };
  };

  swaparr = mkService {
    name = "Swaparr";
    optionPath = ["arr" "swaparr"];
    ociImages.application = {
      # renovate: datasource=docker depName=ghcr.io/thijmengthn/swaparr
      default = "ghcr.io/thijmengthn/swaparr:0.12.0@sha256:c7fd9327b173df20d73f93f3d74e3a20434b9c64df0cecdf72e3a96c32e6687c";
      repository = "ghcr.io/thijmengthn/swaparr";
      role = "application";
    };
    secrets = ["swaparr"];
    credentials = [
      (credential.sops "Radarr API key" ["radarr" "apiKey"])
      (credential.sops "Sonarr API key" ["sonarr" "apiKey"])
      (credential.sops "Lidarr API key" ["lidarr" "apiKey"])
      (credential.sops "Readarr API key" ["swaparr" "readarrApiKey"])
    ];
    setup = setup "arr" 80 ["media-server" "full"];
  };
}
