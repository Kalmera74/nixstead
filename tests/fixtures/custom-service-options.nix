{
  nixstead.preset = "full";
  nixstead.host.user = {
    enable = true;
    name = "api-service-user";
    uid = 1234;
  };
  nixstead.host.ports = {
    http = 18080;
    https = 18443;
  };
  nixstead.host.network.exposure.services = {
    nginx = "public";
    tdarr = "public";
  };
  nixstead.services = {
    nginx.enable = true;
    arr = {
      radarr = {
        enable = true;
        port = 17878;
      };
      sonarr = {
        enable = true;
        port = 18989;
      };
      lidarr = {
        enable = true;
        port = 18686;
      };
      readarr = {
        enable = true;
        port = 18787;
      };
      bazarr = {
        enable = true;
        port = 16767;
      };
      prowlarr = {
        enable = true;
        port = 19696;
      };
      qbittorrent = {
        enable = true;
        port = 18000;
        paths = {
          savePath = "/srv/nixstead-api/torrents";
          tempPath = "/srv/nixstead-api/torrents-temp";
        };
      };
    };
    media = {
      jellyfin = {
        enable = true;
        port = 18096;
      };
      seerr = {
        enable = true;
        port = 15055;
      };
      tdarr = {
        server = true;
        port = 18265;
        serverPort = 18266;
        paths = {
          cacheDir = "/srv/nixstead-api/tdarr-cache";
          dataDir = "/srv/nixstead-api/tdarr";
          mediaDir = "/srv/nixstead-api/media";
        };
      };
      komga.port = 25601;
      kavita = {
        enable = true;
        port = 15000;
        paths.dataDir = "/srv/nixstead-api/kavita";
      };
      audiobookshelf = {
        port = 23378;
        paths.dataDir = "/var/lib/audiobookshelf-api";
      };
      kiwix = {
        port = 19090;
        paths.dataDir = "/srv/nixstead-api/kiwix";
      };
      immich = {
        port = 22283;
        paths.mediaLocation = "/srv/nixstead-api/immich";
      };
      romm = {
        port = 28182;
        paths = {
          dataDir = "/srv/nixstead-api/romm";
          libraryDir = "/srv/nixstead-api/roms";
        };
      };
      tubearchivist = {
        port = 28183;
        paths = {
          dataDir = "/srv/nixstead-api/tubearchivist";
          mediaDir = "/srv/nixstead-api/tubearchivist-media";
        };
      };
    };
    dev = {
      grafana = {
        port = 23001;
        paths.dataDir = "/srv/nixstead-api/grafana";
      };
      prometheus = {
        port = 29091;
        paths.stateDir = "/var/lib/prometheus-api";
      };
      loki = {
        port = 23100;
        paths.dataDir = "/srv/nixstead-api/loki";
      };
      redis.port = 26379;
      rabbitmq.port = 25672;
      postgresql.port = 25432;
      mongodb.port = 27018;
      forgejo = {
        port = 23000;
        paths = {
          stateDir = "/srv/nixstead-api/forgejo";
          repositoryDir = "/srv/nixstead-api/forgejo-repositories";
        };
      };
      gitea = {
        enable = true;
        port = 23002;
        paths.stateDir = "/srv/nixstead-api/gitea";
      };
      pgadmin.port = 25050;
      seaweedfs = {
        enable = true;
        port = 18888;
        masterPort = 19333;
        paths.dataDir = "/srv/nixstead-api/seaweed";
      };
      uptimekuma = {
        port = 23010;
        paths.dataDir = "/srv/nixstead-api/uptimekuma";
      };
      ntfy.port = 22586;
    };
    localai = {
      ollama = {
        port = 21434;
        paths.modelsDir = "/srv/nixstead-api/ollama-models";
      };
      llamacpp = {
        port = 28084;
        ollamaModel = "qwen3.8:latest";
      };
      stablediffusioncpp = {
        port = 21234;
        paths = {
          modelFile = "/srv/nixstead-api/stable-diffusion/model.safetensors";
          modelFiles."motion-module" = "/srv/nixstead-api/stable-diffusion/animatediff/mm_sd_v15_v2.ckpt";
          loraDir = "/srv/nixstead-api/stable-diffusion/loras";
          embeddingsDir = "/srv/nixstead-api/stable-diffusion/embeddings";
          upscalersDir = "/srv/nixstead-api/stable-diffusion/upscalers";
        };
        settings.threads = 8;
      };
      openwebui.port = 28081;
    };
    productivity = {
      paperless = {
        port = 28982;
        paths.dataDir = "/srv/nixstead-api/paperless";
      };
      nextcloud = {
        port = 28083;
        paths.dataDir = "/srv/nixstead-api/nextcloud";
      };
      n8n.port = 25678;
      stirlingpdf.port = 28082;
      seafile = {
        port = 28184;
        paths.dataDir = "/srv/nixstead-api/seafile";
      };
      wallabag = {
        port = 28185;
        paths.dataDir = "/srv/nixstead-api/wallabag";
      };
      linkwarden = {
        port = 28186;
        paths.dataDir = "/srv/nixstead-api/linkwarden";
      };
      snapotter = {
        port = 28187;
        paths.dataDir = "/srv/nixstead-api/snapotter";
        auth.enable = false;
      };
      mealie.port = 28188;
      actualbudget.port = 28189;
      miniflux.port = 28190;
      searxng.port = 28191;
    };
    syncthing = {
      port = 28384;
      transferPort = 32000;
      discoveryPort = 31027;
    };
    scrutiny = {
      port = 28192;
      influxdbPort = 28086;
    };
    vaultwarden = {
      port = 28222;
      paths.backupDir = "/srv/nixstead-api/vaultwarden-backup";
    };
    homeassistant = {
      port = 28123;
      paths.dataDir = "/srv/nixstead-api/homeassistant";
    };
    homepage.port = 22525;
  };
}
