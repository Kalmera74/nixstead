{
  lib,
  registry,
  mkSystem,
  closureDrvPath,
  hasFailedAssertion,
  publicModules,
  publicClosureModules,
  customPortSystem,
  externalOllamaSystem,
  customCaSystem,
  templateFlake,
  templateConfiguration,
}: {
  publicClosureCoverage = lib.attrNames publicClosureModules == lib.attrNames publicModules;
  localPortListenersCovered = lib.all (
    entry:
      !entry.local
      || !(entry.defaults ? port)
      || lib.elem "port" (entry.listeners.settingsTcpPorts or [])
  ) (lib.attrValues registry);
  serviceDomainsFollowHostBase = let
    defaultConfig = (mkSystem publicModules.arr).config;
    customBaseConfig =
      (mkSystem [
        publicModules.arr
        {nixstead.host.network.baseDomain = "hm";}
      ]).config;
    explicitDomainConfig =
      (mkSystem [
        publicModules.arr
        {
          nixstead.host.network.baseDomain = "hm";
          nixstead.services.arr.radarr.domain = "movies.example.test";
        }
      ]).config;
  in
    registry.radarr.defaults.subdomain
    == "radarr"
    && registry.radarr.defaults.domain == "radarr.home.arpa"
    && defaultConfig.nixstead.services.arr.radarr.domain == "radarr.home.arpa"
    && defaultConfig.nixstead.serviceRegistry.radarr.settings.domain == "radarr.home.arpa"
    && customBaseConfig.nixstead.services.arr.radarr.domain == "radarr.hm"
    && customBaseConfig.nixstead.serviceRegistry.radarr.settings.domain == "radarr.hm"
    && explicitDomainConfig.nixstead.services.arr.radarr.domain == "movies.example.test"
    && explicitDomainConfig.nixstead.serviceRegistry.radarr.settings.domain == "movies.example.test";
  templateFollowsNixpkgs =
    lib.hasInfix ''inputs.nixpkgs.follows = "nixpkgs";''
    (builtins.readFile templateFlake);
  templateEnablesZsh =
    (mkSystem [publicModules.default templateConfiguration]).config.programs.zsh.enable;
  arrDefinesMediaGroup = let
    evaluated = (mkSystem publicClosureModules.arr).config;
  in
    builtins.hasAttr evaluated.nixstead.host.groups.media evaluated.users.groups;
  mediaDefinesMediaGroup = let
    evaluated = (mkSystem publicClosureModules.media).config;
  in
    builtins.hasAttr evaluated.nixstead.host.groups.media evaluated.users.groups;
  arrLoopbackFirewall =
    !lib.elem 7878
    (mkSystem [
      publicModules.arr
      {nixstead.services.arr.radarr.enable = true;}
    ]).config.networking.firewall.allowedTCPPorts;
  arrPublicFirewall =
    lib.elem 7878
    (mkSystem [
      publicModules.arr
      {
        nixstead.services.arr.radarr.enable = true;
        nixstead.host.network.exposure.services.radarr = "public";
      }
    ]).config.networking.firewall.allowedTCPPorts;
  arrLanFirewall = let
    evaluated =
      (mkSystem [
        publicModules.arr
        {
          nixstead.services.arr.radarr.enable = true;
          nixstead.host.network.exposure = {
            services.radarr = "lan";
            lan.interfaces = ["eth0"];
          };
        }
      ]).config.networking.firewall;
  in
    !lib.elem 7878 evaluated.allowedTCPPorts
    && lib.elem 7878 evaluated.interfaces.eth0.allowedTCPPorts;
  arrLanSourceFirewall = let
    evaluated =
      (mkSystem [
        publicModules.arr
        {
          nixstead.services.arr.radarr.enable = true;
          nixstead.host.network.exposure = {
            services.radarr = "lan";
            lan.sourceNetworks = ["192.168.50.0/24"];
          };
        }
      ]).config;
  in
    evaluated.networking.nftables.enable
    && lib.hasInfix "192.168.50.0/24" evaluated.networking.firewall.extraInputRules
    && lib.hasInfix "7878" evaluated.networking.firewall.extraInputRules;
  syncthingLanFirewallFollowsOptions = let
    evaluated =
      (mkSystem [
        publicModules.syncthing
        {
          nixstead.services.syncthing = {
            enable = true;
            port = 28384;
            transferPort = 32000;
            discoveryPort = 31027;
          };
          nixstead.host.network.exposure = {
            services.syncthing = "lan";
            lan.interfaces = ["eth0"];
          };
        }
      ]).config.networking.firewall.interfaces.eth0;
  in
    !lib.elem 28384 evaluated.allowedTCPPorts
    && lib.elem 32000 evaluated.allowedTCPPorts
    && lib.elem 32000 evaluated.allowedUDPPorts
    && lib.elem 31027 evaluated.allowedUDPPorts;
  syncthingProxyUsesAcceptedHostHeader = let
    evaluated = customPortSystem.config;
    domain = evaluated.nixstead.serviceRegistry.syncthing.settings.domain;
    extraConfig = evaluated.services.nginx.virtualHosts.${domain}.locations."/".extraConfig;
  in
    lib.hasInfix "proxy_set_header Host localhost;" extraConfig
    && evaluated.services.syncthing.guiAddress == "127.0.0.1:28384"
    && !evaluated.services.syncthing.settings.gui.insecureAdminAccess;
  arrTailnetFirewall = let
    evaluated =
      (mkSystem [
        publicModules.arr
        {
          nixstead.services.arr.radarr.enable = true;
          nixstead.host.network.exposure.services.radarr = "tailnet";
        }
      ]).config.networking.firewall;
  in
    !lib.elem 7878 evaluated.allowedTCPPorts
    && lib.elem 7878 evaluated.interfaces.tailscale0.allowedTCPPorts;
  nginxLoopbackFirewall =
    (mkSystem [
      publicModules.nginx
      {nixstead.services.nginx.enable = true;}
    ]).config.networking.firewall.allowedTCPPorts
    == [];
  nginxPublicFirewall =
    (mkSystem [
      publicModules.nginx
      {
        nixstead.services.nginx.enable = true;
        nixstead.host.network.exposure.services.nginx = "public";
      }
    ]).config.networking.firewall.allowedTCPPorts
    == [80 443];
  redisLoopbackBind =
    (mkSystem [
      publicModules.dev
      {nixstead.services.dev.redis.enable = true;}
    ]).config.services.redis.servers."".bind
    == "127.0.0.1";
  databasesDefaultLoopback = let
    resolved = (mkSystem publicModules.dev).config.nixstead.serviceRegistry;
  in
    lib.all (id: resolved.${id}.exposure == "loopback") [
      "redis"
      "rabbitmq"
      "postgresql"
      "mongodb"
    ];
  containerLoopbackPublish =
    (mkSystem [
      publicModules.media
      {nixstead.services.media.romm.enable = true;}
    ]).config.virtualisation.oci-containers.containers.romm.ports
    == ["127.0.0.1:8182:8080"];
  containerLanPublish =
    (mkSystem [
      publicModules.media
      {
        nixstead.services.media.romm.enable = true;
        nixstead.host.network = {
          lan = "192.168.50.10";
          exposure = {
            services.romm = "lan";
            lan.interfaces = ["eth0"];
          };
        };
      }
    ]).config.virtualisation.oci-containers.containers.romm.ports
    == ["192.168.50.10:8182:8080"];
  containerDeploymentsPinnedAndHardened = let
    containers = customPortSystem.config.virtualisation.oci-containers.containers;
    hasOption = prefix: container: lib.any (lib.hasPrefix prefix) container.extraOptions;
  in
    lib.length (lib.attrNames containers)
    == 22
    && lib.all (
      container:
        builtins.match ".*@sha256:[0-9a-f]{64}" container.image
        != null
        && hasOption "--memory=" container
        && hasOption "--cpus=" container
        && hasOption "--pids-limit=" container
        && hasOption "--health-cmd=" container
        && lib.elem "--security-opt=no-new-privileges=true" container.extraOptions
        && (container.capabilities.AUDIT_WRITE or null) == false
        && (container.capabilities.MKNOD or null) == false
    ) (lib.attrValues containers);
  statefulContainerReadOnlyCoverage = let
    containers = customPortSystem.config.virtualisation.oci-containers.containers;
    readOnlyContainers = [
      "romm-db"
      "tubearchivist-redis"
      "seafile-db"
      "seafile-memcached"
      "wallabag-db"
      "wallabag-redis"
      "linkwarden-db"
      "linkwarden-meilisearch"
      "snapotter-db"
      "snapotter-redis"
      "swaparr-radarr"
      "swaparr-sonarr"
      "swaparr-lidarr"
      "swaparr-readarr"
    ];
  in
    lib.all (name: lib.elem "--read-only" containers.${name}.extraOptions) readOnlyContainers;
  containerNetworksAreCentralized = let
    evaluated = customPortSystem.config;
    containers = evaluated.virtualisation.oci-containers.containers;
    networkUnits =
      lib.filterAttrs (
        _: service:
          service.script
          != null
          && lib.hasInfix "docker network create" service.script
      )
      evaluated.systemd.services;
  in
    lib.length (lib.attrNames networkUnits)
    == 6
    && containers.romm.networks == ["romm-net"]
    && containers.tubearchivist.networks == ["tubearchivist-net"]
    && containers.seafile.networks == ["seafile-net"]
    && containers.wallabag.networks == ["wallabag-net"]
    && containers.linkwarden.networks == ["linkwarden-net"]
    && containers.snapotter.networks == ["snapotter-net"]
    && containers.snapotter-db.networks == ["snapotter-net"]
    && containers.snapotter-redis.networks == ["snapotter-net"];
  containerIdentityAndTimezoneFollowHost = let
    evaluated = customPortSystem.config;
    containers = evaluated.virtualisation.oci-containers.containers;
  in
    containers.romm.environment.TZ
    == evaluated.nixstead.host.locale.timeZone
    && containers.tubearchivist.environment.TZ == evaluated.nixstead.host.locale.timeZone
    && containers.seafile.environment.TIME_ZONE == evaluated.nixstead.host.locale.timeZone
    && containers.snapotter.environment.TZ == evaluated.nixstead.host.locale.timeZone
    && containers.tubearchivist.environment.HOST_UID == toString evaluated.nixstead.host.user.uid
    && containers.tubearchivist.environment.HOST_GID == toString evaluated.nixstead.host.groups.mediaGid
    && containers.snapotter.environment.PUID == toString evaluated.nixstead.host.user.uid
    && containers.snapotter.environment.PGID == toString evaluated.nixstead.host.groups.mediaGid
    && containers.snapotter.environment.AUTH_ENABLED == "false"
    && evaluated.users.groups.${evaluated.nixstead.host.groups.media}.gid == evaluated.nixstead.host.groups.mediaGid;
  unpinnedContainerImagesRejected = let
    floating = builtins.tryEval (closureDrvPath [
      publicModules.media
      {
        nixstead.services.media.romm = {
          enable = true;
          images.application = "ghcr.io/rommapp/romm:latest";
        };
      }
    ]);
    untagged = builtins.tryEval (closureDrvPath [
      publicModules.media
      {
        nixstead.services.media.romm = {
          enable = true;
          images.application = "ghcr.io/rommapp/romm@sha256:2b7a1714b287f69b081ad2a63bb8c2fa673666a17b2f21322b580b0cd51cb266";
        };
      }
    ]);
  in
    !floating.success && !untagged.success;
  generatedContainerImageOverridesApply = let
    image = "ghcr.io/rommapp/romm:5.1.0@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    evaluated =
      (mkSystem [
        publicModules.services
        {nixstead.containerImages.overrides.romm.application = image;}
      ]).config;
  in
    evaluated.nixstead.services.media.romm.images.application == image;
  directContainerImageOverridesWin = let
    generated = "ghcr.io/rommapp/romm:5.1.0@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    direct = "ghcr.io/rommapp/romm:5.0.0@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    evaluated =
      (mkSystem [
        publicModules.services
        {
          nixstead.containerImages.overrides.romm.application = generated;
          nixstead.services.media.romm.images.application = direct;
        }
      ]).config;
  in
    evaluated.nixstead.services.media.romm.images.application == direct;
  containerImageRegistryMetadataIsConsistent = lib.all (
    entry:
      lib.all (
        image:
          lib.elem image.role ["application" "database" "cache" "search"]
          && lib.hasPrefix "${image.repository}:" image.default
          && builtins.match ".*@sha256:[0-9a-f]{64}" image.default != null
      ) (lib.attrValues entry.ociImages)
  ) (lib.attrValues registry);
  unknownContainerImageOverrideRejected = hasFailedAssertion [
    publicModules.services
    {
      nixstead.containerImages.overrides.romm.unknown = "ghcr.io/rommapp/romm:5.1.0@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    }
  ] "Every nixstead.containerImages.overrides entry must name a registry-managed OCI service and component";
  mismatchedContainerImageRepositoryRejected = hasFailedAssertion [
    publicModules.services
    {
      nixstead.containerImages.overrides.romm.application = "example.invalid/romm:5.1.0@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    }
  ] "Every nixstead.containerImages.overrides value must use the component repository declared in the service registry";
  containerLanSourceForward = let
    evaluated =
      (mkSystem [
        publicModules.media
        {
          nixstead.services.media.romm.enable = true;
          nixstead.host.network = {
            lan = "192.168.50.10";
            exposure = {
              services.romm = "lan";
              lan = {
                interfaces = ["eth0"];
                sourceNetworks = ["192.168.50.0/24"];
              };
            };
          };
        }
      ]).config;
  in
    lib.hasInfix "192.168.50.0/24" evaluated.networking.firewall.extraInputRules
    && lib.hasInfix "ct original proto-dst { 8182 }"
    evaluated.networking.nftables.tables."nixstead-service-exposure".content;
  arrPortsFollowOptions = let
    evaluated = customPortSystem.config;
    inherit (evaluated) services;
    resolved = evaluated.nixstead.serviceRegistry;
  in
    services.radarr.settings.server.port
    == resolved.radarr.settings.port
    && services.sonarr.settings.server.port == resolved.sonarr.settings.port
    && services.lidarr.settings.server.port == resolved.lidarr.settings.port
    && services.readarr.settings.server.port == resolved.readarr.settings.port
    && services.bazarr.listenPort == resolved.bazarr.settings.port
    && services.prowlarr.settings.server.port == resolved.prowlarr.settings.port
    && services.qbittorrent.webuiPort == resolved.qbittorrent.settings.port;
  mediaPortsFollowOptions = let
    evaluated = customPortSystem.config;
    resolved = evaluated.nixstead.serviceRegistry;
  in
    evaluated.services.seerr.port
    == resolved.seerr.settings.port
    && evaluated.services.komga.settings.server.port == resolved.komga.settings.port
    && evaluated.services.kavita.settings.Port == resolved.kavita.settings.port
    && evaluated.services.audiobookshelf.port == resolved.audiobookshelf.settings.port
    && evaluated.services.tdarr.server.webUIPort == resolved.tdarr.settings.port
    && evaluated.services.tdarr.server.serverPort == resolved.tdarr.settings.serverPort
    && lib.hasInfix (toString resolved.jellyfin.settings.port) evaluated.systemd.services.jellyfin.preStart
    && lib.hasInfix ("--port " + toString resolved.kiwix.settings.port)
    evaluated.systemd.services.kiwix-serve.serviceConfig.ExecStart;
  devPortsFollowOptions = let
    evaluated = customPortSystem.config;
    resolved = evaluated.nixstead.serviceRegistry;
    services = evaluated.services;
  in
    services.grafana.settings.server.http_port
    == resolved.grafana.settings.port
    && services.prometheus.port == resolved.prometheus.settings.port
    && services.loki.configuration.server.http_listen_port == resolved.loki.settings.port
    && services.redis.servers."".port == resolved.redis.settings.port
    && services.rabbitmq.port == resolved.rabbitmq.settings.port
    && services.postgresql.settings.port == resolved.postgresql.settings.port
    && lib.hasInfix ("net.port: " + toString resolved.mongodb.settings.port) services.mongodb.extraConfig
    && services.forgejo.settings.server.HTTP_PORT == resolved.forgejo.settings.port
    && services.gitea.settings.server.HTTP_PORT == resolved.gitea.settings.port
    && services.pgadmin.port == resolved.pgadmin.settings.port
    && services.ntfy-sh.settings."listen-http"
    == "127.0.0.1:${toString resolved.ntfy.settings.port}";
  ntfyBootstrapUsesNativeHasher = let
    script = customPortSystem.config.systemd.services.ntfy-bootstrap-credentials.script;
  in
    lib.hasInfix "ntfy" script
    && lib.hasInfix "user hash" script
    && !lib.hasInfix "mkpasswd" script;
  credentialRegistryMetadata =
    lib.all (entry: entry ? credentials) (lib.attrValues registry)
    && (lib.elemAt registry.nextcloud.credentials 1).source.pathOption == ["adminPasswordFile"]
    && (lib.head registry.miniflux.credentials).source.envKey == "ADMIN_USERNAME"
    && (lib.head registry.ntfy.credentials).source.path == ["adminUsername"]
    && (lib.elemAt registry.ntfy.credentials 1).source.pathOption == ["adminPasswordFile"]
    && (lib.elemAt registry.syncthing.credentials 1).source.pathOption == ["guiPasswordFile"]
    && (lib.elemAt registry.syncthing.credentials 1).source.fallbackPathOption == ["paths" "configDir"]
    && (lib.head registry.mealie.credentials).source.value == "changeme@example.com"
    && (lib.head registry.openwebui.credentials).source.envKey == "WEBUI_ADMIN_EMAIL"
    && (lib.head registry.tubearchivist.credentials).source.path == ["tubearchivist" "username"];
  preseededCredentialFiles = let
    evaluated =
      (mkSystem [
        publicModules.default
        {
          nixstead.services = {
            productivity = {
              nextcloud = {
                enable = true;
                adminPasswordFile = "/run/secrets/nextcloud-admin";
              };
              miniflux = {
                enable = true;
                adminCredentialsFile = "/run/secrets/miniflux-admin.env";
              };
            };
            dev.ntfy = {
              enable = true;
              adminPasswordFile = "/run/secrets/ntfy-admin";
            };
            syncthing = {
              enable = true;
              guiPasswordFile = "/run/secrets/syncthing-gui";
            };
            localai.openwebui = {
              enable = true;
              ollamaUrl = "http://ollama.example.test:11434";
              environmentFile = "/run/secrets/open-webui-admin.env";
            };
          };
        }
      ]).config;
  in
    evaluated.services.nextcloud.config.adminpassFile
    == "/run/secrets/nextcloud-admin"
    && evaluated.services.miniflux.adminCredentialsFile == "/run/secrets/miniflux-admin.env"
    && evaluated.services.open-webui.environmentFile == "/run/secrets/open-webui-admin.env"
    && evaluated.services.syncthing.guiPasswordFile == "/run/secrets/syncthing-gui"
    && evaluated.nixstead.serviceRegistry.ntfy.settings.adminPasswordFile == "/run/secrets/ntfy-admin"
    && !lib.elem
    "miniflux-bootstrap-credentials.service"
    evaluated.systemd.services.miniflux.requires
    && !lib.hasInfix
    "openssl rand -hex 24"
    evaluated.systemd.services.ntfy-bootstrap-credentials.script;
  stableDiffusionCppSupportsSplitVideoPipelines = let
    modelFiles = {
      "diffusion-model" = "/srv/nixstead-api/wan/wan2.1-t2v-1.3b.safetensors";
      vae = "/srv/nixstead-api/wan/wan_2.1_vae.safetensors";
      t5xxl = "/srv/nixstead-api/wan/umt5-xxl-encoder-Q8_0.gguf";
    };
    evaluated =
      (mkSystem [
        publicModules.localai
        {
          nixstead.services.localai.stablediffusioncpp = {
            enable = true;
            paths = {
              modelFile = null;
              inherit modelFiles;
            };
            settings."diffusion-fa" = true;
          };
        }
      ]).config;
    unit = evaluated.systemd.services.stable-diffusion-cpp;
    command = unit.serviceConfig.ExecStart;
    modelPaths = builtins.attrValues modelFiles;
  in
    lib.all (
      name: lib.hasInfix "--${name} ${modelFiles.${name}}" command
    ) (builtins.attrNames modelFiles)
    && lib.hasInfix "--diffusion-fa" command
    && !(lib.hasInfix "--model /var/lib/stable-diffusion-cpp" command)
    && lib.all (path: lib.elem path unit.unitConfig.RequiresMountsFor) modelPaths
    && unit.unitConfig.ConditionPathExists == modelPaths;
  applicationPortsFollowRegistry = let
    evaluated = customPortSystem.config;
    resolved = evaluated.nixstead.serviceRegistry;
    containers = evaluated.virtualisation.oci-containers.containers;
    stableDiffusionCppUnit = evaluated.systemd.services.stable-diffusion-cpp;
    stableDiffusionCppExec = stableDiffusionCppUnit.serviceConfig.ExecStart;
    published = id: internal: "127.0.0.1:${toString resolved.${id}.settings.port}:${toString internal}";
  in
    evaluated.services.ollama.port
    == resolved.ollama.settings.port
    && evaluated.services.ollama.modelsDir == evaluated.nixstead.services.localai.ollama.paths.modelsDir
    && evaluated.services.llama-cpp.settings.port == resolved.llamacpp.settings.port
    && evaluated.services.ollama.user == "ollama"
    && lib.elem
    evaluated.services.ollama.modelsDir
    evaluated.systemd.services.ollama.unitConfig.RequiresMountsFor
    && lib.elem
    evaluated.nixstead.host.groups.media
    evaluated.systemd.services.ollama.serviceConfig.SupplementaryGroups
    && evaluated.systemd.services.llama-cpp.serviceConfig.User == "ollama"
    && evaluated.systemd.services.llama-cpp.environment.HOME == evaluated.services.ollama.home
    && evaluated.systemd.services.llama-cpp.environment.OLLAMA_MODELS == evaluated.services.ollama.modelsDir
    && evaluated.systemd.services.llama-cpp.serviceConfig.RuntimeDirectory == "llama-cpp"
    && lib.elem
    "${evaluated.services.ollama.modelsDir}:/run/llama-cpp/ollama-models"
    evaluated.systemd.services.llama-cpp.serviceConfig.BindReadOnlyPaths
    && lib.elem
    evaluated.services.ollama.modelsDir
    evaluated.systemd.services.llama-cpp.unitConfig.RequiresMountsFor
    && lib.elem
    evaluated.nixstead.host.groups.media
    evaluated.systemd.services.llama-cpp.serviceConfig.SupplementaryGroups
    && lib.elem "ollama.service" evaluated.systemd.services.llama-cpp.requires
    && lib.hasInfix
    ("--listen-port " + toString resolved.stablediffusioncpp.settings.port)
    stableDiffusionCppExec
    && lib.hasInfix
    "--model /srv/nixstead-api/stable-diffusion/model.safetensors"
    stableDiffusionCppExec
    && lib.hasInfix
    "--motion-module /srv/nixstead-api/stable-diffusion/animatediff/mm_sd_v15_v2.ckpt"
    stableDiffusionCppExec
    && lib.hasInfix "--serve-html-path /nix/store/" stableDiffusionCppExec
    && lib.elem
    "/srv/nixstead-api/stable-diffusion/model.safetensors"
    stableDiffusionCppUnit.unitConfig.ConditionPathExists
    && lib.elem
    "/srv/nixstead-api/stable-diffusion/animatediff/mm_sd_v15_v2.ckpt"
    stableDiffusionCppUnit.unitConfig.ConditionPathExists
    && lib.elem
    "/srv/nixstead-api/stable-diffusion/animatediff/mm_sd_v15_v2.ckpt"
    stableDiffusionCppUnit.unitConfig.RequiresMountsFor
    && lib.elem
    "/srv/nixstead-api/stable-diffusion/upscalers"
    stableDiffusionCppUnit.unitConfig.RequiresMountsFor
    && stableDiffusionCppUnit.serviceConfig.User == "stable-diffusion-cpp"
    && evaluated.services.open-webui.port == resolved.openwebui.settings.port
    && evaluated.services.paperless.port == resolved.paperless.settings.port
    && lib.any (
      listener: listener.port == resolved.nextcloud.settings.port
    )
    evaluated.services.nginx.virtualHosts.${resolved.nextcloud.settings.domain}.listen
    && evaluated.services.n8n.environment.N8N_PORT == toString resolved.n8n.settings.port
    && evaluated.services.stirling-pdf.environment.SERVER_PORT == toString resolved.stirlingpdf.settings.port
    && evaluated.services.mealie.port == resolved.mealie.settings.port
    && evaluated.services.actual.settings.port == resolved.actualbudget.settings.port
    && evaluated.services.miniflux.config.LISTEN_ADDR
    == "127.0.0.1:${toString resolved.miniflux.settings.port}"
    && evaluated.services.searx.settings.server.port == resolved.searxng.settings.port
    && lib.elem "redis-searx.service" evaluated.systemd.services.searx.requires
    && lib.elem "redis-searx.service" evaluated.systemd.services.searx.after
    && evaluated.services.syncthing.guiAddress
    == "127.0.0.1:${toString resolved.syncthing.settings.port}"
    && evaluated.services.scrutiny.settings.web.listen.port == resolved.scrutiny.settings.port
    && evaluated.services.scrutiny.settings.web.influxdb.port
    == resolved.scrutiny.settings.influxdbPort
    && evaluated.services.immich.port == resolved.immich.settings.port
    && evaluated.services.vaultwarden.config.ROCKET_PORT == resolved.vaultwarden.settings.port
    && evaluated.services.home-assistant.config.http.server_port
    == resolved.homeassistant.settings.port
    && evaluated.services.home-assistant.config.http.server_host == "127.0.0.1"
    && evaluated.services.home-assistant.config.http.trusted_proxies
    == [
      "127.0.0.1"
      "::1"
    ]
    && evaluated.services.homepage-dashboard.listenPort == resolved.homepage.settings.port
    && lib.elem (published "seafile" 80) containers.seafile.ports
    && lib.elem (published "romm" 8080) containers.romm.ports
    && lib.elem (published "tubearchivist" 8000) containers.tubearchivist.ports
    && lib.elem (published "uptimekuma" 3001) containers.uptimekuma.ports
    && lib.elem (published "wallabag" 80) containers.wallabag.ports
    && lib.elem (published "linkwarden" 3000) containers.linkwarden.ports
    && lib.elem (published "snapotter" 1349) containers.snapotter.ports;
  authentikOptionsReachServices = let
    evaluated =
      (mkSystem [
        publicModules.authentik
        {
          nixstead.services.authentik = {
            enable = true;
            port = 19000;
            workerPort = 19001;
            metricsPort = 19300;
            workerMetricsPort = 19301;
            httpsPort = 19443;
            paths.dataDir = "/srv/nixstead-api/authentik";
          };
        }
      ]).config;
    server = evaluated.systemd.services.authentik-server;
    worker = evaluated.systemd.services.authentik-worker;
    databaseSetup = evaluated.systemd.services.authentik-database-setup;
  in
    server.environment.AUTHENTIK_LISTEN__HTTP
    == "127.0.0.1:19000"
    && server.environment.AUTHENTIK_LISTEN__HTTPS == "127.0.0.1:19443"
    && server.environment.AUTHENTIK_LISTEN__METRICS == "127.0.0.1:19300"
    && worker.environment.AUTHENTIK_LISTEN__HTTP == "127.0.0.1:19001"
    && worker.environment.AUTHENTIK_LISTEN__METRICS == "127.0.0.1:19301"
    && server.environment.AUTHENTIK_STORAGE__FILE__PATH == "/srv/nixstead-api/authentik"
    && server.environment.AUTHENTIK_SECRET_KEY == "file:///run/secrets/authentik/secretKey"
    && !lib.elem "authentik" evaluated.services.postgresql.ensureDatabases
    && lib.hasInfix "CREATE ROLE authentik LOGIN" databaseSetup.script
    && lib.hasInfix "CREATE DATABASE authentik OWNER authentik TEMPLATE template0" databaseSetup.script
    && lib.elem "authentik-database-setup.service" server.requires
    && lib.elem "authentik-database-setup.service" worker.requires;
  minifluxDatabaseSetupUsesTemplate0 = let
    evaluated = customPortSystem.config;
    databaseSetup = evaluated.systemd.services.miniflux-database-setup;
    databasePort = toString evaluated.services.postgresql.settings.port;
  in
    !evaluated.services.miniflux.createDatabaseLocally
    && !lib.elem "miniflux" evaluated.services.postgresql.ensureDatabases
    && evaluated.services.miniflux.config.DATABASE_URL
    == "user=miniflux host=/run/postgresql port=${databasePort} dbname=miniflux"
    && lib.hasInfix "--port ${databasePort}" databaseSetup.script
    && lib.hasInfix "CREATE ROLE miniflux LOGIN" databaseSetup.script
    && lib.hasInfix "CREATE DATABASE miniflux OWNER miniflux TEMPLATE template0" databaseSetup.script
    && lib.elem "miniflux-database-setup.service" evaluated.systemd.services.miniflux.requires;
  immichHomepageWidget = let
    evaluated = customPortSystem.config;
    renderedServices = builtins.toJSON evaluated.services.homepage-dashboard.services;
  in
    lib.hasInfix ''"Immich"'' renderedServices
    && lib.hasInfix ''"type":"immich"'' renderedServices
    && lib.hasInfix ''"version":2'' renderedServices
    && lib.hasInfix "HOMEPAGE_VAR_IMMICHAPIKEY" renderedServices
    && lib.hasInfix "HOMEPAGE_VAR_IMMICHAPIKEY=" evaluated.sops.templates."homepage.env".content;
  tdarrHomepageWidget = let
    renderedServices = builtins.toJSON customPortSystem.config.services.homepage-dashboard.services;
  in
    lib.hasInfix ''"Tdarr"'' renderedServices
    && lib.hasInfix ''"type":"tdarr"'' renderedServices;
  homepageCatalogCoverage = let
    expectedTypes = {
      radarr = "radarr";
      sonarr = "sonarr";
      lidarr = "lidarr";
      readarr = "readarr";
      bazarr = "bazarr";
      prowlarr = "prowlarr";
      qbittorrent = "qbittorrent";
      jellyfin = "jellyfin";
      seerr = "seerr";
      tdarr = "tdarr";
      komga = "komga";
      kavita = "kavita";
      audiobookshelf = "audiobookshelf";
      immich = "immich";
      romm = "romm";
      tubearchivist = "tubearchivist";
      grafana = "grafana";
      gitea = "gitea";
      uptimekuma = "uptimekuma";
      paperless = "paperlessngx";
      nextcloud = "nextcloud";
      linkwarden = "linkwarden";
      pihole = "pihole";
      proxmox = "proxmox";
      truenas = "truenas";
    };
  in
    lib.all (
      id:
        registry.${id}.homepage
        != null
        && registry.${id}.homepage.widget.type == expectedTypes.${id}
    ) (lib.attrNames expectedTypes)
    && registry.prometheus.homepage != null
    && !(registry.prometheus.homepage ? widget);
  newHomepageWidgetsRender = let
    evaluated = customPortSystem.config;
    renderedGroups = evaluated.services.homepage-dashboard.services;
    renderedCards =
      lib.foldl' (
        cards: group:
          lib.foldl' (groupCards: service: groupCards // service) {} (
            lib.concatLists (lib.attrValues group)
          )
          // cards
      ) {}
      renderedGroups;
    expectedTypes = {
      Komga = "komga";
      RomM = "romm";
      TubeArchivist = "tubearchivist";
      Grafana = "grafana";
      Gitea = "gitea";
      Paperless = "paperlessngx";
      Nextcloud = "nextcloud";
      Linkwarden = "linkwarden";
    };
  in
    lib.all (
      title: renderedCards.${title}.widget.type == expectedTypes.${title}
    ) (lib.attrNames expectedTypes)
    && renderedCards.Grafana.widget.version == 2
    && !(renderedCards.Prometheus ? widget);
  homepageWidgetTargetsFollowTopology = let
    evaluated =
      (mkSystem [
        publicModules.default
        {
          nixstead.host.network = {
            lan = "192.0.2.10";
            truenas = "192.0.2.30";
            exposure = {
              default = "public";
              services.linkwarden = "loopback";
            };
          };
          nixstead.services = {
            homepage.enable = true;
            productivity = {
              paperless.enable = true;
              linkwarden.enable = true;
            };
            truenas.enable = true;
          };
        }
      ]).config;
    renderedCards =
      lib.foldl' (
        cards: group:
          lib.foldl' (groupCards: service: groupCards // service) {} (
            lib.concatLists (lib.attrValues group)
          )
          // cards
      ) {}
      evaluated.services.homepage-dashboard.services;
    allowedHosts = evaluated.services.paperless.settings.PAPERLESS_ALLOWED_HOSTS;
  in
    renderedCards.Paperless.widget.url
    == "http://127.0.0.1:28981"
    && renderedCards.Linkwarden.widget.url == "http://127.0.0.1:8186"
    && renderedCards.TrueNAS.widget.url == "http://192.0.2.30:80"
    && lib.hasInfix "127.0.0.1" allowedHosts
    && lib.hasInfix "192.0.2.10" allowedHosts;
  homepageHostShortcutsRender = let
    evaluated =
      (mkSystem [
        publicModules.homepage
        {
          nixstead.services.homepage = {
            enable = true;
            shortcuts = [
              {
                name = "NixOS Search";
                href = "https://search.nixos.org/packages";
                icon = "nixos.png";
                description = "Packages";
              }
            ];
          };
        }
      ]).config;
    renderedServices = builtins.toJSON evaluated.services.homepage-dashboard.services;
  in
    lib.hasInfix ''"Shortcuts"'' renderedServices
    && lib.hasInfix ''"NixOS Search"'' renderedServices
    && lib.hasInfix ''"href":"https://search.nixos.org/packages"'' renderedServices
    && lib.hasInfix ''"icon":"https://raw.githubusercontent.com/homarr-labs/dashboard-icons/main/png/nixos.png"'' renderedServices;
  homepageLayoutPlacesDevToolsAfterShortcuts = let
    evaluated =
      (mkSystem [
        publicModules.homepage
        {nixstead.services.homepage.enable = true;}
      ]).config;
    sectionNames = map (section: lib.head (lib.attrNames section)) evaluated.services.homepage-dashboard.settings.layout;
  in
    lib.hasInfix ''"Shortcuts","Dev Tools"'' (builtins.toJSON sectionNames);
  newHomepageWidgetSecretsRender = let
    evaluated = customPortSystem.config;
    renderedServices = builtins.toJSON evaluated.services.homepage-dashboard.services;
    renderedEnvironment = evaluated.sops.templates."homepage.env".content;
    requiredSecrets = [
      "komgaUsername"
      "komgaPassword"
      "tubearchivistApiKey"
      "grafanaUsername"
      "grafanaPassword"
      "giteaApiToken"
      "paperlessApiKey"
      "nextcloudToken"
      "linkwardenApiKey"
    ];
  in
    lib.all (
      name: let
        variable = "HOMEPAGE_VAR_${lib.toUpper name}";
      in
        lib.hasInfix variable renderedServices
        && lib.hasInfix "${variable}=" renderedEnvironment
    )
    requiredSecrets;
  applicationPathsFollowTypedOptions = let
    evaluated = customPortSystem.config;
    typed = evaluated.nixstead.services;
    services = evaluated.services;
    containers = evaluated.virtualisation.oci-containers.containers;
    hasVolume = container: volume: lib.elem volume containers.${container}.volumes;
  in
    services.qbittorrent.serverConfig.Preferences.Downloads.SavePath
    == typed.arr.qbittorrent.paths.savePath
    && services.qbittorrent.serverConfig.Preferences.Downloads.TempPath
    == typed.arr.qbittorrent.paths.tempPath
    && services.tdarr.dataDir == typed.media.tdarr.paths.dataDir
    && lib.all (path: lib.elem path evaluated.systemd.services.tdarr-server.serviceConfig.ReadWritePaths) [
      typed.media.tdarr.paths.cacheDir
      typed.media.tdarr.paths.mediaDir
    ]
    && lib.all (path: lib.elem path evaluated.systemd.services.tdarr-node-local.serviceConfig.ReadWritePaths) [
      typed.media.tdarr.paths.cacheDir
      typed.media.tdarr.paths.mediaDir
    ]
    && lib.all (path: lib.elem path evaluated.systemd.services.tdarr-server.unitConfig.RequiresMountsFor) [
      typed.media.tdarr.paths.cacheDir
      typed.media.tdarr.paths.mediaDir
    ]
    && lib.all (path: lib.elem path evaluated.systemd.services.tdarr-node-local.unitConfig.RequiresMountsFor) [
      typed.media.tdarr.paths.cacheDir
      typed.media.tdarr.paths.mediaDir
    ]
    && services.kavita.dataDir == typed.media.kavita.paths.dataDir
    && services.kavita.tokenKeyFile == typed.media.kavita.tokenKeyFile
    && "/var/lib/${services.audiobookshelf.dataDir}" == typed.media.audiobookshelf.paths.dataDir
    && lib.hasInfix "${typed.media.kiwix.paths.dataDir}/library.xml"
    evaluated.systemd.services.kiwix-serve.serviceConfig.ExecStart
    && lib.elem typed.media.kiwix.paths.dataDir
    evaluated.systemd.services.kiwix-library-refresh.unitConfig.RequiresMountsFor
    && services.grafana.dataDir == typed.dev.grafana.paths.dataDir
    && "/var/lib/${services.prometheus.stateDir}" == typed.dev.prometheus.paths.stateDir
    && services.loki.dataDir == typed.dev.loki.paths.dataDir
    && services.loki.configuration.common.path_prefix == services.loki.dataDir
    && services.forgejo.stateDir == typed.dev.forgejo.paths.stateDir
    && services.forgejo.repositoryRoot == typed.dev.forgejo.paths.repositoryDir
    && services.gitea.stateDir == typed.dev.gitea.paths.stateDir
    && lib.hasInfix "${typed.dev.seaweedfs.paths.dataDir}/master"
    evaluated.systemd.services.seaweedfs.serviceConfig.ExecStart
    && lib.hasInfix "${typed.dev.seaweedfs.paths.dataDir}/volume"
    evaluated.systemd.services.seaweedfs.serviceConfig.ExecStart
    && lib.hasInfix "${typed.dev.seaweedfs.paths.dataDir}/filer"
    evaluated.environment.etc."seaweedfs/filer.toml".text
    && services.paperless.dataDir == typed.productivity.paperless.paths.dataDir
    && services.paperless.mediaDir == "${services.paperless.dataDir}/media"
    && services.paperless.consumptionDir == "${services.paperless.dataDir}/consume"
    && services.nextcloud.datadir == typed.productivity.nextcloud.paths.dataDir
    && services.immich.mediaLocation == typed.media.immich.paths.mediaLocation
    && services.vaultwarden.backupDir == typed.vaultwarden.paths.backupDir
    && services.home-assistant.configDir == typed.homeassistant.paths.dataDir
    && hasVolume "seafile" "${typed.productivity.seafile.paths.dataDir}/data:/shared"
    && hasVolume "romm" "${typed.media.romm.paths.dataDir}/resources:/romm/resources"
    && hasVolume "romm" "${typed.media.romm.paths.libraryDir}:/romm/library"
    && hasVolume "tubearchivist" "${typed.media.tubearchivist.paths.dataDir}/cache:/cache"
    && hasVolume "tubearchivist" "${typed.media.tubearchivist.paths.mediaDir}:/youtube"
    && hasVolume "uptimekuma" "${typed.dev.uptimekuma.paths.dataDir}:/app/data"
    && hasVolume "wallabag" "${typed.productivity.wallabag.paths.dataDir}/images:/var/www/wallabag/web/assets/images"
    && hasVolume "linkwarden" "${typed.productivity.linkwarden.paths.dataDir}/data:/data/data"
    && hasVolume "snapotter" "${typed.productivity.snapotter.paths.dataDir}/data:/data"
    && hasVolume "snapotter" "${typed.productivity.snapotter.paths.dataDir}/workspace:/tmp/workspace"
    && hasVolume "snapotter-db" "${typed.productivity.snapotter.paths.dataDir}/postgres:/var/lib/postgresql/data"
    && hasVolume "snapotter-redis" "${typed.productivity.snapotter.paths.dataDir}/redis:/data";
  serviceDefaultsRemainIndependentOfCifs = let
    evaluated =
      (mkSystem [
        publicModules.default
        {
          nixstead.services.arr.qbittorrent.enable = true;
          nixstead.services.media.romm.enable = true;
        }
      ]).config;
  in
    evaluated.nixstead.services.arr.qbittorrent.paths.savePath
    == null
    && evaluated.nixstead.services.arr.qbittorrent.paths.tempPath == null
    && evaluated.nixstead.services.media.romm.paths.dataDir == "/var/lib/romm"
    && evaluated.nixstead.services.media.romm.paths.libraryDir == "/var/lib/romm/library";
  arbitraryCifsSharesDriveFilesystemsAndMountDependencies = let
    evaluated =
      (mkSystem [
        publicModules.default
        ({config, ...}: {
          nixstead.services.cifs = {
            enable = true;
            shares = {
              bulk = {
                source = "//storage.test/bulk";
                mountPoint = "/srv/bulk";
              };
              state = {
                source = "//storage.test/state";
                mountPoint = "/srv/state";
              };
              games = {
                source = "//storage.test/games";
                mountPoint = "/srv/games";
              };
            };
          };
          nixstead.services.arr.qbittorrent = {
            enable = true;
            paths.savePath = "${config.nixstead.services.cifs.shares.bulk.mountPoint}/torrents";
          };
          nixstead.services.media.romm = {
            enable = true;
            paths = {
              dataDir = "${config.nixstead.services.cifs.shares.state.mountPoint}/romm";
              libraryDir = "${config.nixstead.services.cifs.shares.games.mountPoint}/roms";
            };
          };
        })
      ]).config;
  in
    evaluated.fileSystems."/srv/bulk".device
    == "//storage.test/bulk"
    && evaluated.fileSystems."/srv/state".device == "//storage.test/state"
    && evaluated.fileSystems."/srv/games".device == "//storage.test/games"
    && evaluated.nixstead.services.arr.qbittorrent.paths.savePath == "/srv/bulk/torrents"
    && evaluated.nixstead.services.media.romm.paths.dataDir == "/srv/state/romm"
    && evaluated.nixstead.services.media.romm.paths.libraryDir == "/srv/games/roms"
    && lib.elem "/srv/bulk/torrents"
    evaluated.systemd.services.qbittorrent.unitConfig.RequiresMountsFor
    && lib.elem "/srv/state/romm/resources"
    evaluated.systemd.services.docker-romm.unitConfig.RequiresMountsFor;
  duplicateCifsMountRejected = hasFailedAssertion [
    publicModules.default
    {
      nixstead.services.cifs = {
        enable = true;
        shares = {
          one = {
            source = "//storage.test/one";
            mountPoint = "/srv/shared";
          };
          two = {
            source = "//storage.test/two";
            mountPoint = "/srv/shared";
          };
        };
      };
    }
  ] "Enabled CIFS shares must use unique mountPoint values";
  relativeCifsMountRejected = let
    result = builtins.tryEval (closureDrvPath [
      publicModules.default
      {
        nixstead.services.cifs = {
          enable = true;
          shares.any = {
            source = "//storage.test/any";
            mountPoint = "relative/mount";
          };
        };
      }
    ]);
  in
    !result.success;
  publicFoundationPolicyIsOptIn = let
    evaluated = (mkSystem publicModules.base).config;
  in
    !evaluated.nix.gc.automatic
    && !evaluated.nix.settings.auto-optimise-store
    && !evaluated.nixpkgs.config.allowUnfree
    && !evaluated.boot.tmp.cleanOnBoot
    && !evaluated.zramSwap.enable;
  groupedToolFollowsIndependentToggles = let
    packageNames = modules:
      map lib.getName (mkSystem modules).config.environment.systemPackages;
    disabledNames = packageNames publicModules.default;
    adminNames = packageNames [
      publicModules.tools
      {nixstead.tools.enable = true;}
    ];
    allNames = packageNames [
      publicModules.tools
      {
        nixstead.tools = {
          enable = true;
          media.enable = true;
        };
      }
    ];
  in
    !lib.elem "nixstead" disabledNames
    && lib.elem "nixstead" adminNames
    && lib.elem "nixstead" allNames;
  devCatalogDoesNotInstallToolchains = let
    names = map lib.getName (mkSystem publicModules.dev).config.environment.systemPackages;
  in
    !lib.elem "python3" names && !lib.elem "go" names;
  externalUrlsFollowTlsProxy = let
    evaluated = customPortSystem.config;
  in
    evaluated.services.n8n.environment.WEBHOOK_URL
    == "https://${evaluated.nixstead.services.productivity.n8n.domain}"
    && evaluated.virtualisation.oci-containers.containers.romm.environment.ROMM_BASE_URL
    == "https://${evaluated.nixstead.services.media.romm.domain}";
  backupMetadataFollowsTypedPaths = let
    evaluated = customPortSystem.config;
    serviceRegistry = evaluated.nixstead.serviceRegistry;
  in
    serviceRegistry.romm.backup.paths
    == [
      evaluated.nixstead.services.media.romm.paths.dataDir
      evaluated.nixstead.services.media.romm.paths.libraryDir
    ]
    && lib.elem "docker-romm-db.service" serviceRegistry.romm.backup.units
    && serviceRegistry.seafile.backup.paths
    == ["${evaluated.nixstead.services.productivity.seafile.paths.dataDir}/data"]
    && serviceRegistry.seafile.backup.path == lib.head serviceRegistry.seafile.backup.paths;
  scheduledBackupsRequireExplicitRemotePolicy = let
    evaluated =
      (mkSystem [
        publicModules.base
        {
          nixstead.backups = {
            enable = true;
            repository = "ssh://backup@example.test/./borg/nixstead";
            environmentFile = "/run/secrets/nixstead-backup-env";
          };
        }
      ]).config;
    backupExec = evaluated.systemd.services.nixstead-service-backup.serviceConfig.ExecStart;
  in
    evaluated.systemd.timers.nixstead-service-backup.timerConfig.OnCalendar
    == "daily"
    && evaluated.systemd.timers.nixstead-backup-restore-test.timerConfig.OnCalendar == "weekly"
    && evaluated.systemd.services.nixstead-service-backup.environment.NIXSTEAD_BACKUP_REPOSITORY
    == "ssh://backup@example.test/./borg/nixstead"
    && evaluated.systemd.services.nixstead-service-backup.environment.NIXSTEAD_BACKUP_STATE_DIR
    == "/var/lib/nixstead-backups"
    && lib.hasPrefix "/nix/store/" backupExec
    && !lib.hasInfix evaluated.nixstead.host.repositoryPath backupExec;
  periodicServiceSmokeTestsAreStoreBacked = let
    evaluated = (mkSystem publicModules.default).config;
    smokeExec = evaluated.systemd.services.nixstead-service-smoke-test.serviceConfig.ExecStart;
  in
    evaluated.systemd.timers.nixstead-service-smoke-test.timerConfig.OnCalendar
    == "daily"
    && lib.hasPrefix "/nix/store/" smokeExec
    && evaluated.systemd.services.nixstead-service-smoke-test.environment.NIXSTEAD_REGISTRY_FILE != "";
  auxiliaryPortsFollowOptions = let
    evaluated = customPortSystem.config;
    seaweedExec = evaluated.systemd.services.seaweedfs.serviceConfig.ExecStart;
  in
    lib.hasInfix "-master.port=19333" seaweedExec
    && lib.hasInfix "-filer.port=18888" seaweedExec
    && lib.elem 18265 evaluated.networking.firewall.allowedTCPPorts
    && lib.elem 18266 evaluated.networking.firewall.allowedTCPPorts;
  portCollisionRejected = let
    modules = [
      publicModules.arr
      {
        nixstead.services.arr = {
          radarr = {
            enable = true;
            port = 17878;
          };
          sonarr = {
            enable = true;
            port = 17878;
          };
        };
      }
    ];
    result = builtins.tryEval (closureDrvPath modules);
  in
    !result.success
    && hasFailedAssertion modules "Enabled services have TCP listener collisions";
  openWebUiDependencyRejected = let
    modules = [
      publicModules.localai
      {
        nixstead.services.localai = {
          ollama.enable = false;
          openwebui.enable = true;
        };
      }
    ];
    result = builtins.tryEval (closureDrvPath modules);
  in
    !result.success
    && hasFailedAssertion modules "Open WebUI requires";
  openWebUiExternalOllama =
    externalOllamaSystem.config.services.open-webui.environment.OLLAMA_BASE_URL
    == "http://ollama.example.test:11434";
  runtimePathsRejectRelativeValues = let
    result = builtins.tryEval (closureDrvPath [
      publicModules.arr
      {
        nixstead.services.arr.qbittorrent = {
          enable = true;
          paths.savePath = "relative/downloads";
        };
      }
    ]);
  in
    !result.success;
  audiobookshelfPathConstraint = hasFailedAssertion [
    publicModules.media
    {
      nixstead.services.media.audiobookshelf = {
        enable = true;
        paths.dataDir = "/srv/audiobookshelf";
      };
    }
  ] "audiobookshelf.paths.dataDir must be a directory below /var/lib";
  prometheusPathConstraint = hasFailedAssertion [
    publicModules.dev
    {
      nixstead.services.dev.prometheus = {
        enable = true;
        paths.stateDir = "/srv/prometheus";
      };
    }
  ] "prometheus.paths.stateDir must be a directory below /var/lib";
  nginxPortsFollowHostOptions = let
    evaluated = customPortSystem.config;
  in
    evaluated.services.nginx.defaultHTTPListenPort
    == 18080
    && evaluated.services.nginx.defaultSSLListenPort == 18443
    && lib.elem 18080 evaluated.networking.firewall.allowedTCPPorts
    && lib.elem 18443 evaluated.networking.firewall.allowedTCPPorts;
  nginxCaLifecycle = let
    evaluated = customCaSystem.config;
    ca = evaluated.nixstead.services.nginx.ca;
  in
    ca.certificateFile
    == "/run/credentials/nginx-ca.crt"
    && ca.privateKeyFile == "/run/credentials/nginx-ca.key"
    && ca.homeCertificateFile == "/home/certificate-test/.local/share/nixstead/certificate-test-nginx-ca.crt"
    && evaluated.systemd.timers.nginx-local-certificates.timerConfig.OnCalendar == "daily"
    && evaluated.systemd.timers.nginx-local-certificates.timerConfig.Persistent
    && lib.elem "nginx-local-certificates.service" evaluated.systemd.services.nginx.requires
    && lib.elem "sops-install-secrets.service"
    evaluated.systemd.services.nginx-local-certificates.after
    && lib.hasInfix "generate-local-ca-and-certs"
    evaluated.systemd.services.nginx-local-certificates.script
    && !lib.hasInfix "watch.home.arpa" evaluated.systemd.services.nginx-local-certificates.script;
  generatedNginxCaKeyIsRootOnly = let
    source = builtins.readFile ../modules/services/nginx/nginx.nix;
  in
    lib.hasInfix ''install -m 0600 -o root -g root'' source
    && lib.hasInfix ''chown root:root "$managed_ca_key"'' source
    && lib.hasInfix ''chmod 0600 "$managed_ca_key"'' source;
  sshOptionsFollowHost = let
    key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey api@example";
    evaluated =
      (mkSystem [
        publicModules.base
        {
          nixstead.host = {
            ports.ssh = 2222;
            ssh = {
              authorizedKeys = [key];
              passwordAuthentication = false;
              rootLogin = "no";
            };
            user = {
              enable = true;
              name = "ssh-api-user";
              uid = 1235;
            };
          };
        }
      ]).config;
  in
    evaluated.services.openssh.ports
    == [2222]
    && lib.elem 2222 evaluated.networking.firewall.allowedTCPPorts
    && !evaluated.services.openssh.settings.PasswordAuthentication
    && !evaluated.services.openssh.settings.KbdInteractiveAuthentication
    && evaluated.services.openssh.settings.PermitRootLogin == "no"
    && evaluated.users.users.ssh-api-user.openssh.authorizedKeys.keys == [key]
    && evaluated.environment.sessionVariables.SOPS_AGE_KEY_FILE
    == "/home/ssh-api-user/.local/share/nixstead/sops-age-key.txt"
    && lib.hasInfix "/home/ssh-api-user/.config/sops/age/keys.txt"
    evaluated.system.activationScripts.nixstead-user-generated-files.text;
  sshAllowsPasswordOnlyLogin = let
    evaluated =
      (mkSystem [
        publicModules.base
        {
          nixstead.host = {
            ssh = {
              authorizedKeys = [];
              passwordAuthentication = true;
            };
            user = {
              enable = true;
              name = "password-ssh-api-user";
              uid = 1236;
            };
          };
        }
      ]).config;
  in
    evaluated.users.users.password-ssh-api-user.openssh.authorizedKeys.keys
    == []
    && evaluated.services.openssh.settings.PasswordAuthentication
    && evaluated.services.openssh.settings.KbdInteractiveAuthentication;
  generatedFilesDirectoryConstraint = hasFailedAssertion [
    publicModules.base
    {
      nixstead.host.user.generatedFilesDirectory = "generated/../outside-home";
    }
  ] "nixstead.host.user.generatedFilesDirectory must be a non-empty relative subdirectory";
  externalOptions = (mkSystem publicModules.external).config.nixstead.services.pihole.port == 80;
  piholeDnsSyncUsesHomepageCredential = let
    evaluated =
      (mkSystem [
        publicModules.default
        {
          nixstead.host.network = {
            lan = "192.0.2.10";
            pihole = "192.0.2.53";
          };
          nixstead.services = {
            homepage.enable = true;
            pihole.enable = true;
            pihole.dnsSync.enable = true;
          };
        }
      ]).config;
    unit = evaluated.systemd.services.nixstead-pihole-dns-sync;
  in
    unit.serviceConfig.LoadCredential
    == "pihole-password:${evaluated.sops.secrets."homepage/piholeApiKey".path}"
    && lib.elem "multi-user.target" unit.wantedBy
    && lib.hasInfix "--state-file /var/lib/nixstead-pihole-dns-sync/managed-domains.json" unit.serviceConfig.ExecStart
    && lib.hasInfix "--prune-managed" unit.serviceConfig.ExecStart
    && lib.elem
    "nixstead-pihole-dns-sync.service"
    evaluated.sops.secrets."homepage/piholeApiKey".restartUnits;
  piholeDnsSyncWaitsForCredential = let
    evaluated = (mkSystem (publicClosureModules.external ++ [{nixstead.services.pihole.dnsSync.enable = true;}])).config;
  in
    !builtins.hasAttr "nixstead-pihole-dns-sync" evaluated.systemd.services;
  piholeDnsSyncAcceptsExternalCredential = let
    evaluated =
      (mkSystem [
        publicModules.external
        {
          nixstead.host.network = {
            lan = "192.0.2.10";
            pihole = "192.0.2.53";
          };
          nixstead.services.pihole = {
            enable = true;
            dnsSync.enable = true;
            dnsSync.credentialFile = "/run/secrets/pihole-password";
          };
        }
      ]).config;
  in
    evaluated.systemd.services.nixstead-pihole-dns-sync.serviceConfig.LoadCredential
    == "pihole-password:/run/secrets/pihole-password";
  piholeDnsSyncRejectsRelativeCredential = hasFailedAssertion [
    publicModules.external
    {nixstead.services.pihole.dnsSync.credentialFile = "relative/secret";}
  ] "nixstead.services.pihole.dnsSync.credentialFile must be an absolute runtime path";
  presetOverride =
    !(
      mkSystem [
        publicModules.default
        {
          nixstead.preset = "full";
          nixstead.services.productivity.nextcloud.enable = false;
        }
      ]
    ).config.nixstead.services.productivity.nextcloud.enable;
}
