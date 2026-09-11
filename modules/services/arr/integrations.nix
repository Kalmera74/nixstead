{
  config,
  lib,
  pkgs,
  serviceRegistry,
  ...
}: let
  arr = config.nixstead.services.arr;
  cfg = arr.integrations;
  storage = arr.storage;
  appMetadata =
    lib.mapAttrs (_: entry: entry.api.downloadClient)
    (lib.filterAttrs (_: entry: entry.api != null && entry.api ? downloadClient) serviceRegistry);
  eligible = lib.filterAttrs (id: metadata: arr.${id}.enable && storage.libraries.${metadata.library} != null) appMetadata;
  selectedApps = lib.filterAttrs (_: metadata: cfg.${metadata.relationship}.enable || cfg.storageToQbittorrent.enable) eligible;
  downloadSelected = selectedApps != {};
  prowlarrApps = lib.filterAttrs (id: _: cfg.prowlarr.${id}.enable && arr.prowlarr.enable && arr.${id}.enable) appMetadata;
  bazarrApps = lib.filterAttrs (id: _: cfg.bazarr.${id}.enable && arr.bazarr.enable && arr.${id}.enable) (lib.filterAttrs (id: _: id != "lidarr") appMetadata);
  sabnzbdApps = lib.filterAttrs (id: _: cfg.sabnzbd.${id}.enable && arr.sabnzbd.enable && arr.${id}.enable) appMetadata;
  seerrCfg =
    config.nixstead.services.media.seerr.integrations or {
      enable = false;
      jellyfin.enable = false;
      destinations = {};
    };
  seerrDestinations = lib.optionalAttrs seerrCfg.enable (lib.filterAttrs (_: destination: destination.enable) seerrCfg.destinations);
  seerrSelected = seerrCfg.enable && (seerrCfg.jellyfin.enable || seerrDestinations != {});
  seerrJellyfinKeyFile =
    if seerrCfg.jellyfin.apiKeyFile != null
    then seerrCfg.jellyfin.apiKeyFile
    else config.sops.secrets."homepage/${serviceRegistry.jellyfin.homepage.widget.secrets.key}".path;
  seerrCredentials = lib.optionalAttrs seerrSelected ({seerr = {};} // lib.mapAttrs (_: _: {}) seerrDestinations);
  ntfyApps = lib.filterAttrs (_: value: value.enable) cfg.ntfy;
  prowlarrSelected = prowlarrApps != {} || cfg.prowlarrSyncProfiles != {};
  selected = prowlarrSelected || ntfyApps != {} || seerrSelected || sabnzbdApps != {} || downloadSelected || prowlarrApps != {} || bazarrApps != {};
  credentialApps = lib.mapAttrs (_: _: {}) ntfyApps // seerrCredentials // sabnzbdApps // lib.optionalAttrs (sabnzbdApps != {}) {sabnzbd = {};} // clientApps // prowlarrApps // bazarrApps // lib.optionalAttrs prowlarrSelected {prowlarr = {};} // lib.optionalAttrs (bazarrApps != {}) {bazarr = {};};
  clientApps = lib.filterAttrs (_: metadata: cfg.${metadata.relationship}.enable) selectedApps;
  pathOption = description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      inherit description;
    };
  desired = pkgs.writeText "arr-relationships.json" (builtins.toJSON {
    inherit (cfg) dryRun relocation;
    applications =
      lib.mapAttrsToList (id: metadata: {
        application = id;
        inherit (cfg) dryRun relocation;
        storageToQbittorrent = cfg.storageToQbittorrent.enable;
        downloadClient = cfg.${metadata.relationship}.enable;
        categoryPath =
          if storage.torrents.root == null
          then null
          else "${storage.torrents.root}/${metadata.library}";
        rootFolder = storage.libraries.${metadata.library};
        rootFields = lib.optionalAttrs (id == "lidarr") {
          name = "Nixstead music";
          defaultQualityProfileId = cfg.lidarr.qualityProfileId;
          defaultMetadataProfileId = cfg.lidarr.metadataProfileId;
        };
        torrentRoot = storage.torrents.root;
        incomplete = storage.torrents.incomplete;
        qbittorrentEndpoint = "http://127.0.0.1:${toString arr.qbittorrent.port}";
        endpoint = "http://127.0.0.1:${toString arr.${id}.port}";
      })
      selectedApps;
    ntfy =
      lib.mapAttrsToList (id: value: {
        application = id;
        applicationEndpoint = "http://127.0.0.1:${toString arr.${id}.port}";
        inherit (value) endpoint topics events;
      })
      ntfyApps;
    seerr =
      if !seerrSelected
      then null
      else {
        endpoint = "http://127.0.0.1:${toString config.nixstead.serviceRegistry.seerr.settings.port}";
        jellyfin =
          if !seerrCfg.jellyfin.enable
          then null
          else {
            endpoint = "http://127.0.0.1:${toString config.nixstead.services.media.jellyfin.port}";
            inherit (seerrCfg.jellyfin) libraries libraryPolicy;
          };
        destinations =
          lib.mapAttrsToList (id: destination: {
            application = id;
            endpoint = "http://127.0.0.1:${toString config.nixstead.serviceRegistry.${id}.settings.port}";
            inherit (destination) existingServer qualityProfileId rootFolder is4k isDefault searchOnRequest;
          })
          seerrDestinations;
      };
    sabnzbdEndpoint = "http://127.0.0.1:${toString arr.sabnzbd.port}";
    sabnzbdApplications =
      lib.mapAttrsToList (id: metadata: {
        application = id;
        inherit (cfg) dryRun;
        endpoint = "http://127.0.0.1:${toString arr.${id}.port}";
        complete = storage.usenet.complete;
        incomplete = storage.usenet.incomplete;
        categoryPath = "${storage.usenet.complete}/${metadata.library}";
        rootFolder = storage.libraries.${metadata.library};
        rootFields = lib.optionalAttrs (id == "lidarr") {
          name = "Nixstead music";
          defaultQualityProfileId = cfg.lidarr.qualityProfileId;
          defaultMetadataProfileId = cfg.lidarr.metadataProfileId;
        };
      })
      sabnzbdApps;
    bazarrApplications =
      lib.mapAttrsToList (id: _: {
        application = id;
        endpoint = "http://127.0.0.1:${toString arr.${id}.port}";
      })
      bazarrApps;
    bazarrEndpoint = "http://127.0.0.1:${toString arr.bazarr.port}";
    prowlarrSyncProfiles = cfg.prowlarrSyncProfiles;
    prowlarrApplications =
      lib.mapAttrsToList (id: _: {
        application = id;
        endpoint = "http://127.0.0.1:${toString arr.${id}.port}";
        inherit (cfg.prowlarr.${id}) syncLevel categories animeCategories tags;
      })
      prowlarrApps;
    prowlarrEndpoint = "http://127.0.0.1:${toString arr.prowlarr.port}";
    qbittorrentEndpoint = "http://127.0.0.1:${toString arr.qbittorrent.port}";
    metricsFile = "/run/nixstead-metrics/arr.prom";
  });
in {
  options.nixstead.services.arr.integrations = {
    active = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      internal = true;
      default = selected;
      description = "Whether any relationship is selected.";
    };
    enable = lib.mkEnableOption "eligible ARR API relationships (ensure only)";
    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Fetch and report redacted proposed changes without application mutations.";
    };
    relocation = lib.mkOption {
      type = lib.types.enum ["refuse" "allow"];
      default = "refuse";
      description = "Explicit permission to change managed category paths when existing torrents could be relocated.";
    };
    storageToQbittorrent.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable && arr.qbittorrent.enable && eligible != {} && storage.torrents.root != null;
      description = "Ensure download categories for selected TV, movies and music relationships.";
    };
    qbittorrentToSonarr.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable && arr.qbittorrent.enable && arr.sonarr.enable && storage.libraries.tv != null && storage.torrents.root != null;
      description = "Ensure Sonarr's authenticated qBittorrent client and explicitly selected root folder.";
    };
    qbittorrentToRadarr.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable && arr.qbittorrent.enable && arr.radarr.enable && storage.libraries.movies != null && storage.torrents.root != null;
      description = "Ensure Radarr's authenticated qBittorrent client and selected movies root.";
    };
    qbittorrentToLidarr.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable && arr.qbittorrent.enable && arr.lidarr.enable && storage.libraries.music != null && storage.torrents.root != null && cfg.lidarr.qualityProfileId != null && cfg.lidarr.metadataProfileId != null;
      description = "Ensure Lidarr's authenticated qBittorrent client and selected music root.";
    };
    ntfy = lib.genAttrs ["sonarr" "radarr" "lidarr"] (id: {
      enable = lib.mkEnableOption "selected native ${id} ntfy notifications";
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Explicit ntfy server URL. Configuration changes send a native test notification.";
      };
      topics = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Explicit ntfy topics.";
      };
      tokenFile = pathOption "Runtime ntfy access token file, delivered only to the selected application relationship.";
      events = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        default = {
          onHealthIssue = true;
          onHealthRestored = true;
        };
        description = "Owned native notification event toggles. Other events remain unchanged.";
      };
    });
    sabnzbd =
      lib.mapAttrs (id: metadata: {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = cfg.enable && arr.sabnzbd.enable && arr.${id}.enable && storage.usenet.complete != null && storage.usenet.incomplete != null && storage.libraries.${metadata.library} != null && (id != "lidarr" || (cfg.lidarr.qualityProfileId != null && cfg.lidarr.metadataProfileId != null));
          description = "Ensure SABnzbd category and ${id} download client with declared Usenet storage.";
        };
      })
      appMetadata;
    bazarr = lib.genAttrs ["sonarr" "radarr"] (id: {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable && arr.bazarr.enable && arr.${id}.enable;
        description = "Manage only Bazarr connection fields for ${id}; subtitle policy remains a user choice.";
      };
    });
    prowlarrSyncProfiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enableRss = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable RSS for this explicit sync profile.";
          };
          enableAutomaticSearch = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable automatic searches.";
          };
          enableInteractiveSearch = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable interactive searches.";
          };
          minimumSeeders = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 1;
            description = "Minimum seeders for this profile.";
          };
        };
      });
      default = {};
      description = "Explicit Prowlarr sync profiles to ensure. Assigning profiles to user-owned indexers remains a user choice.";
    };
    prowlarr =
      lib.mapAttrs (id: _: {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = cfg.enable && arr.prowlarr.enable && arr.${id}.enable;
          description = "Ensure the authenticated Prowlarr registration for ${id}.";
        };
        syncLevel = lib.mkOption {
          type = lib.types.enum ["fullSync" "addOnly" "disabled"];
          default = "fullSync";
          description = "Selected Prowlarr application synchronization level.";
        };
        categories = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.ints.positive);
          default = null;
          description = "Explicit synchronized categories. Null preserves application defaults and UI choices.";
        };
        animeCategories = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.ints.positive);
          default = null;
          description = "Explicit Sonarr anime categories; ignored for other applications.";
        };
        tags = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.ints.positive);
          default = null;
          description = "Existing Prowlarr tag IDs filtering indexer synchronization. Null leaves tags unowned.";
        };
      })
      appMetadata;
    lidarr = {
      qualityProfileId = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Explicit Lidarr quality profile for a newly declared music root.";
      };
      metadataProfileId = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Explicit Lidarr metadata profile for a newly declared music root.";
      };
    };
  };
  config = lib.mkMerge [
    {
      assertions =
        lib.mapAttrsToList (id: metadata: {
          assertion = !cfg.${metadata.relationship}.enable || (arr.qbittorrent.enable && arr.${id}.enable && storage.libraries.${metadata.library} != null && storage.torrents.root != null);
          message = "${metadata.relationship} requires both enabled applications and explicitly selected storage.";
        })
        appMetadata
        ++ lib.mapAttrsToList (id: _: {
          assertion = !cfg.prowlarr.${id}.enable || (arr.prowlarr.enable && arr.${id}.enable);
          message = "Prowlarr registration for ${id} requires both enabled applications.";
        })
        appMetadata
        ++ lib.mapAttrsToList (id: metadata: {
          assertion = !cfg.sabnzbd.${id}.enable || (arr.sabnzbd.enable && arr.${id}.enable && storage.usenet.complete != null && storage.usenet.incomplete != null && storage.libraries.${metadata.library} != null);
          message = "SABnzbd ${id} integration requires both applications and explicit Usenet and library paths.";
        })
        appMetadata
        ++ map (id: {
          assertion = !cfg.bazarr.${id}.enable || (arr.bazarr.enable && arr.${id}.enable);
          message = "Bazarr connection for ${id} requires both enabled applications.";
        }) ["sonarr" "radarr"]
        ++ [
          {
            assertion = !(cfg.qbittorrentToLidarr.enable || cfg.sabnzbd.lidarr.enable) || (cfg.lidarr.qualityProfileId != null && cfg.lidarr.metadataProfileId != null);
            message = "Lidarr requires explicitly selected quality and metadata profiles.";
          }
        ];
    }
    (lib.mkIf selected {
      assertions =
        lib.mapAttrsToList (id: value: {
          assertion = arr.${id}.enable && value.topics != [] && value.endpoint != "" && value.tokenFile != null && lib.hasPrefix "/" value.tokenFile && !lib.hasPrefix "/nix/store/" value.tokenFile;
          message = "ntfy ${id} requires the application, topics, an endpoint and a runtime access token file.";
        })
        ntfyApps
        ++ [
          {
            assertion = !prowlarrSelected || arr.prowlarr.enable;
            message = "Prowlarr synchronization profiles require Prowlarr.";
          }
          {
            assertion = !seerrSelected || config.nixstead.services.media.seerr.enable;
            message = "Seerr relationships require Seerr to be enabled.";
          }
          {
            assertion = !(seerrSelected && seerrCfg.jellyfin.enable) || (config.nixstead.services.media.jellyfin.enable && lib.hasPrefix "/" seerrJellyfinKeyFile && !lib.hasPrefix "/nix/store/" seerrJellyfinKeyFile);
            message = "Seerr requires enabled Jellyfin and an API-key file outside the Nix store.";
          }
          {
            assertion = !(seerrSelected && seerrCfg.jellyfin.enable) || ((seerrCfg.jellyfin.libraryPolicy == "explicit") == (seerrCfg.jellyfin.libraries != []));
            message = "Seerr Jellyfin libraries must be nonempty only with the explicit library policy; discovery policies need no IDs.";
          }
          {
            assertion = lib.all (id: arr.${id}.enable && (seerrDestinations.${id}.existingServer != null || (seerrDestinations.${id}.qualityProfileId != null && seerrDestinations.${id}.rootFolder != null))) (lib.attrNames seerrDestinations);
            message = "Seerr destinations require enabled applications and either an explicit existing server selection or explicit root folders and quality profiles.";
          }
          {
            assertion = lib.all (id: let destination = seerrDestinations.${id}; in destination.existingServer == null || (destination.qualityProfileId == null && destination.rootFolder == null && !destination.is4k && !destination.isDefault && !destination.searchOnRequest)) (lib.attrNames seerrDestinations);
            message = "Seerr existing-server connections preserve UI policy; omit qualityProfileId, rootFolder, is4k, isDefault and searchOnRequest in this mode.";
          }
          {
            assertion = !downloadSelected || arr.qbittorrent.enable;
            message = "ARR download relationships require qBittorrent.";
          }
          {
            assertion = !downloadSelected || storage.torrents.root != null;
            message = "ARR integration requires explicitly configured torrent storage.";
          }
          {
            assertion = !cfg.qbittorrentToSonarr.enable || storage.libraries.tv != null;
            message = "Sonarr integration requires an explicitly selected library root.";
          }
          {
            assertion = !downloadSelected || (storage.torrents.root == arr.qbittorrent.paths.savePath && storage.torrents.incomplete == arr.qbittorrent.paths.tempPath);
            message = "Conflicting ARR integration paths: effective qBittorrent savePath/tempPath must agree with storage.torrents.";
          }
          {
            assertion = arr.credentials.enable;
            message = "ARR integration requires shared runtime credentials.";
          }
        ];
      nixstead.services.arr.credentials = {
        enable = lib.mkDefault true;
        consumers = lib.mapAttrs (_: _: ["nixstead-arr-reconcile.service"]) (credentialApps // lib.optionalAttrs downloadSelected {qbittorrent = {};});
      };
      users.users.nixstead-arr-reconcile = {
        isSystemUser = true;
        group = "nixstead-arr-reconcile";
      };
      users.groups.nixstead-arr-reconcile = {};
      systemd.services.nixstead-arr-reconcile = {
        description = "Ensure selected authenticated ARR relationships";
        after = lib.optional downloadSelected "qbittorrent.service" ++ lib.optional (seerrSelected && seerrCfg.jellyfin.enable) "jellyfin.service" ++ map (id: "${id}.service") (lib.attrNames credentialApps);
        requires = lib.optional downloadSelected "qbittorrent.service" ++ lib.optional (seerrSelected && seerrCfg.jellyfin.enable) "jellyfin.service" ++ map (id: "${id}.service") (lib.attrNames credentialApps);
        wantedBy = ["multi-user.target"];
        restartTriggers = [desired];
        serviceConfig = {
          Type = "oneshot";
          User = "nixstead-arr-reconcile";
          Group = "nixstead-arr-reconcile";
          StateDirectory = "nixstead-arr-integrations";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "nixstead-metrics";
          RuntimeDirectoryMode = "0755";
          RuntimeDirectoryPreserve = true;
          UMask = "0077";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          TimeoutStartSec = 180;
          LoadCredential =
            lib.optionals downloadSelected [
              "username:/run/nixstead-credentials/qbittorrent/username"
              "password:/run/nixstead-credentials/qbittorrent/password"
            ]
            ++ lib.mapAttrsToList (id: value: "ntfy-${id}:${value.tokenFile}") ntfyApps
            ++ lib.optional (seerrSelected && seerrCfg.jellyfin.enable) "jellyfin:${seerrJellyfinKeyFile}"
            ++ map (id: "${id}:/run/nixstead-credentials/${id}/api-key") (lib.attrNames credentialApps);
          ExecStart = "${pkgs.python3}/bin/python3 ${../.}/arr/reconcile.py ${desired}";
        };
      };
      systemd.timers.nixstead-arr-reconcile = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitInactiveSec = "5m";
          RandomizedDelaySec = "20s";
        };
      };
      services.prometheus.exporters.node = {
        enabledCollectors = ["textfile"];
        extraFlags = ["--collector.textfile.directory=/run/nixstead-metrics"];
      };
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "nixstead-status";
          runtimeInputs = [pkgs.jq pkgs.systemd];
          text = ''
            ${lib.optionalString arr.credentials.autoSync.enable ''
              systemctl show nixstead-credentials-sync.service nixstead-credentials-sync-refresh.service --property=ActiveState,Result
              if [[ -r /run/nixstead-credential-enrollment/status.json ]]; then
                jq . /run/nixstead-credential-enrollment/status.json
              fi
            ''}
            systemctl show nixstead-arr-reconcile.service --property=ActiveState,Result
            if [[ -r /var/lib/nixstead-arr-integrations/status.json ]]; then
              jq . /var/lib/nixstead-arr-integrations/status.json
            fi
          '';
        })
      ];
    })
  ];
}
