{
  lib,
  mkSystem,
  hasFailedAssertion,
  publicModules,
}: let
  configured =
    (mkSystem [
      publicModules.default
      {
        nixstead.services.arr = {
          sonarr.enable = true;
          qbittorrent.enable = true;
          storage = {
            root = "/data";
            manageDirectories = true;
          };
          integrations.enable = true;
          monitoring.enable = true;
        };
        nixstead.services.dev.prometheus.enable = true;
      }
    ]).config;
  bare = (mkSystem [publicModules.arr {nixstead.services.arr.enable = true;}]).config;
  disabled = (mkSystem [publicModules.arr {nixstead.services.arr.monitoring.enable = true;}]).config;
  seerr =
    (mkSystem [
      publicModules.media
      {
        system.stateVersion = lib.mkForce "24.11";
        nixstead.services.media.seerr.enable = true;
        services.seerr.configDir = "/var/lib/seerr-custom";
      }
    ]).config;
  existingSeerr =
    (mkSystem [
      publicModules.default
      {
        nixstead.services = {
          homepage.enable = true;
          arr = {
            sonarr = {
              enable = true;
              port = 8991;
            };
            radarr.enable = true;
          };
          media.seerr = {
            enable = true;
            integrations = {
              enable = true;
              destinations.sonarr.existingServer = {};
              destinations.radarr.existingServer.name = "Existing movies";
            };
          };
        };
      }
    ]).config;
  disabledExistingSeerr =
    (mkSystem [
      publicModules.default
      {
        nixstead.services.media.seerr = {
          enable = true;
          integrations = {
            enable = true;
            destinations.sonarr.existingServer = {};
          };
        };
        nixstead.services.arr.sonarr.enable = false;
      }
    ]).config;
  jellyfinModule = {
    nixstead.services.media = {
      jellyfin.enable = true;
      seerr = {
        enable = true;
        integrations.enable = true;
      };
    };
  };
  discoveredSeerr = (mkSystem [publicModules.default jellyfinModule]).config;
  explicitSeerr =
    (mkSystem [
      publicModules.default
      jellyfinModule
      {nixstead.services.media.seerr.integrations.jellyfin.libraries = ["selected-id"];}
    ]).config;
  customJellyfinKey =
    (mkSystem [
      publicModules.default
      jellyfinModule
      {nixstead.services.media.seerr.integrations.jellyfin.apiKeyFile = "/run/custom-jellyfin-key";}
    ]).config;
  catalog =
    (mkSystem [
      publicModules.arr
      {
        nixstead.services.arr = {
          sonarr.enable = true;
          sabnzbd = {
            enable = true;
            paths.dataDir = "/var/lib/sab-custom";
          };
          shelfmark = {
            enable = true;
            paths.ingestDir = "/srv/books";
          };
          monitoring.enable = true;
        };
      }
    ]).config;
  manualHomepage =
    (mkSystem [
      publicModules.default
      {
        nixstead.services = {
          homepage.enable = true;
          arr = {
            sonarr.enable = true;
            credentials.enable = false;
            swaparr.enable = true;
          };
        };
      }
    ]).config;
  canonicalOverride =
    (mkSystem [
      publicModules.arr
      {
        nixstead.services.arr = {
          sonarr.enable = true;
          credentials = {
            enable = true;
            apiKeyFiles.sonarr = "/run/secrets/sonarr/apiKey";
          };
        };
        sops.secrets."sonarr/apiKey" = {};
      }
    ]).config;
in {
  seerrDiscoversWithoutLibraryIdsOrHomepage =
    discoveredSeerr.nixstead.services.media.seerr.integrations.jellyfin.enable
    && discoveredSeerr.nixstead.services.media.seerr.integrations.jellyfin.libraryPolicy == "auto"
    && discoveredSeerr.nixstead.services.media.seerr.integrations.jellyfin.libraries == []
    && !discoveredSeerr.nixstead.services.homepage.enable
    && discoveredSeerr.sops.secrets."homepage/jellyfinApiKey".mode == "0400"
    && lib.elem "nixstead-arr-reconcile.service" discoveredSeerr.sops.secrets."homepage/jellyfinApiKey".restartUnits
    && lib.elem "jellyfin:/run/secrets/homepage/jellyfinApiKey" discoveredSeerr.systemd.services.nixstead-arr-reconcile.serviceConfig.LoadCredential
    && lib.elem "jellyfin.service" discoveredSeerr.systemd.services.nixstead-arr-reconcile.requires
    && builtins.isString discoveredSeerr.system.build.toplevel.drvPath;
  existingExplicitLibrarySelectionsStillWork =
    explicitSeerr.nixstead.services.media.seerr.integrations.jellyfin.libraryPolicy
    == "explicit"
    && builtins.isString explicitSeerr.system.build.toplevel.drvPath;
  customJellyfinKeyDoesNotRequireDefaultSecret =
    !(customJellyfinKey.sops.secrets ? "homepage/jellyfinApiKey")
    && lib.elem "jellyfin:/run/custom-jellyfin-key" customJellyfinKey.systemd.services.nixstead-arr-reconcile.serviceConfig.LoadCredential;
  discoveryDoesNotMixExplicitSelections = hasFailedAssertion [
    publicModules.default
    jellyfinModule
    {
      nixstead.services.media.seerr.integrations.jellyfin = {
        libraryPolicy = "auto";
        libraries = ["ambiguous-policy"];
      };
    }
  ] "discovery policies need no IDs";
  explicitLibraryPolicyNeedsSelections = hasFailedAssertion [
    publicModules.default
    jellyfinModule
    {nixstead.services.media.seerr.integrations.jellyfin.libraryPolicy = "explicit";}
  ] "discovery policies need no IDs";
  disablingJellyfinRemovesDefaultRelationship = let
    disabled = (mkSystem [publicModules.default jellyfinModule {nixstead.services.media.jellyfin.enable = lib.mkForce false;}]).config;
  in
    !disabled.nixstead.services.media.seerr.integrations.jellyfin.enable
    && !(disabled.systemd.services ? nixstead-arr-reconcile)
    && !(disabled.sops.secrets ? "homepage/jellyfinApiKey");
  jellyfinRelationshipCanBeDisabled = let
    disabled = (mkSystem [publicModules.default jellyfinModule {nixstead.services.media.seerr.integrations.jellyfin.enable = false;}]).config;
  in
    !(disabled.systemd.services ? nixstead-arr-reconcile)
    && !(disabled.sops.secrets ? "homepage/jellyfinApiKey");
  canonicalCredentialDelivery =
    configured.nixstead.serviceRegistry.sonarr.api.sopsSecret
    == "sonarr/apiKey"
    && configured.nixstead.serviceRegistry.sonarr.api.stateFile == "${configured.services.sonarr.dataDir}/config.xml"
    && configured.nixstead.services.arr.credentials.autoSync.enable
    && configured.nixstead.services.arr.credentials.autoSync.sourceFile == "/etc/nixos/secrets/test.yaml"
    && !(configured.sops.secrets ? "nixstead/credential-document")
    && configured.systemd.services.nixstead-credentials-sync.serviceConfig.RuntimeDirectoryMode == "0700"
    && configured.systemd.services.nixstead-credential-sonarr.serviceConfig.RemainAfterExit
    && configured.systemd.timers.nixstead-credentials-sync.timerConfig.Unit == "nixstead-credentials-sync-refresh.service"
    && lib.elem "nixstead-credentials-sync.service" configured.systemd.services.nixstead-credential-sonarr.requires
    && lib.elem "/run/nixstead-credentials/sonarr/ready" configured.systemd.services.prometheus-exportarr-sonarr-exporter.unitConfig.ConditionPathExists
    && lib.elem "password:/run/nixstead-credentials/qbittorrent/password" configured.systemd.services.qbittorrent.serviceConfig.LoadCredential
    && !(configured.sops.secrets ? "homepage/sonarrApiKey")
    && !(configured.sops.secrets ? "homepage/qbittorrentPassword")
    && !(configured.sops.secrets ? "qbittorrent/passwordHash");
  homepageWithoutSharingStillUsesCanonicalSops =
    manualHomepage.sops.secrets ? "sonarr/apiKey"
    && !(manualHomepage.sops.secrets ? "homepage/sonarrApiKey")
    && !(manualHomepage.sops.secrets ? "swaparr/sonarrApiKey")
    && builtins.isString manualHomepage.system.build.toplevel.drvPath;
  canonicalSopsFileOverrideAccepted = builtins.isString canonicalOverride.system.build.toplevel.drvPath;
  manualCredentialDeliveryRemainsAvailable = let
    manual =
      (mkSystem [
        publicModules.arr
        {
          nixstead.services.arr = {
            sonarr.enable = true;
            credentials = {
              enable = true;
              autoSync.enable = false;
            };
          };
        }
      ]).config;
  in
    manual.sops.secrets ? "nixstead/credential-document"
    && !(manual.systemd.services ? nixstead-credentials-sync)
    && manual.systemd.timers.nixstead-credential-sonarr.timerConfig.Unit == "nixstead-credential-sonarr-refresh.service";
  automaticSourceFollowsConfiguredDocument = let
    external =
      (mkSystem [
        publicModules.arr
        {
          nixstead.secrets.sopsFile = lib.mkForce "/var/lib/secrets/custom.yaml";
          nixstead.services.arr.qbittorrent.enable = true;
        }
      ]).config;
  in
    external.nixstead.services.arr.credentials.autoSync.sourceFile
    == "/var/lib/secrets/custom.yaml"
    && external.nixstead.serviceRegistry.qbittorrent.credentialSopsFile == "/var/lib/secrets/custom.yaml";
  immutableAutomaticSourceRejected = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr = {
        qbittorrent.enable = true;
        credentials.autoSync.sourceFile = "/nix/store/immutable-secrets.yaml";
      };
    }
  ] "absolute writable source path";
  separateCredentialSourceRejected = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr = {
        sonarr.enable = true;
        credentials = {
          enable = true;
          apiKeyFiles.sonarr = "/run/other-key";
        };
      };
    }
  ] "canonical entry in the host SOPS document";
  differentSopsKeyRejected = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr = {
        sonarr.enable = true;
        credentials = {
          enable = true;
          apiKeyFiles.sonarr = "/run/secrets/sonarr/apiKey";
        };
      };
      sops.secrets."sonarr/apiKey".key = "homepage/sonarrApiKey";
    }
  ] "canonical entry in the host SOPS document";
  separateQbittorrentPasswordRejected = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr.qbittorrent = {
        enable = true;
        passwordFile = "/run/other-password";
      };
    }
  ] "canonical entries in the host SOPS document";
  disablingArrStopsDefaultSeerrConnectionManagement =
    !disabledExistingSeerr.nixstead.services.media.seerr.integrations.destinations.sonarr.enable
    && !disabledExistingSeerr.nixstead.services.arr.integrations.active
    && !(disabledExistingSeerr.systemd.services ? nixstead-arr-reconcile)
    && builtins.isString disabledExistingSeerr.system.build.toplevel.drvPath;
  existingSeerrConnectionsNeedNoNewRequestPolicy =
    existingSeerr.nixstead.services.media.seerr.integrations.destinations.sonarr.enable
    && existingSeerr.nixstead.services.media.seerr.integrations.destinations.sonarr.qualityProfileId == null
    && existingSeerr.nixstead.services.media.seerr.integrations.destinations.sonarr.rootFolder == null
    && existingSeerr.nixstead.services.arr.credentials.enable
    && existingSeerr.nixstead.services.arr.integrations.active
    && !existingSeerr.nixstead.services.arr.integrations.enable
    && existingSeerr.nixstead.services.arr.storage.root == null
    && lib.elem "seerr:/run/nixstead-credentials/seerr/api-key" existingSeerr.systemd.services.nixstead-arr-reconcile.serviceConfig.LoadCredential
    && lib.elem "/run/nixstead-credentials/seerr/homepage.env" existingSeerr.services.homepage-dashboard.environmentFiles
    && lib.elem "nixstead-credential-sonarr.service" existingSeerr.systemd.services.nixstead-arr-reconcile.requires
    && builtins.isString existingSeerr.system.build.toplevel.drvPath;
  existingSeerrCannotManageRequestPolicy = hasFailedAssertion [
    publicModules.default
    {
      nixstead.services.arr.sonarr.enable = true;
      nixstead.services.media.seerr = {
        enable = true;
        integrations = {
          enable = true;
          destinations.sonarr = {
            existingServer = {};
            qualityProfileId = 1;
            rootFolder = "/media/tv";
          };
        };
      };
    }
  ] "existing-server connections preserve UI policy";
  catalogUsesNativeStateAndRestrictedCredentials =
    catalog.nixstead.serviceRegistry.sabnzbd.backup.paths
    == ["/var/lib/sab-custom"]
    && catalog.services.sabnzbd.stateDir == "sab-custom"
    && catalog.services.sabnzbd.configFile == null
    && catalog.services.prometheus.exporters.sabnzbd.servers
    == [
      {
        baseUrl = "http://127.0.0.1:8085";
        apiKeyFile = "/run/nixstead-credentials/sabnzbd/api-key";
      }
    ]
    && builtins.isString catalog.system.build.toplevel.drvPath;
  noImplicitCatalogPolicy =
    !bare.nixstead.services.arr.sabnzbd.enable
    && !bare.nixstead.services.arr.shelfmark.enable;
  shelfmarkNeedsIngest = hasFailedAssertion [publicModules.arr {nixstead.services.arr.shelfmark.enable = true;}] "explicitly selected ingest";
  exporterPortConflict = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr = {
        sonarr.enable = true;
        monitoring = {
          enable = true;
          services.sonarr.port = 8989;
        };
      };
    }
  ] "exporter ports must be unique";
  lidarrUsenetRequiresProfiles = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr = {
        lidarr.enable = true;
        sabnzbd.enable = true;
        storage.root = "/data";
        integrations.sabnzbd.lidarr.enable = true;
      };
    }
  ] "explicitly selected quality and metadata profiles";
  seerrCanonicalState =
    seerr.services.seerr.stateRevision
    == 1
    && seerr.system.stateVersion == "24.11"
    && seerr.nixstead.serviceRegistry.seerr.backup.paths == ["/var/lib/seerr-custom"]
    && seerr.systemd.services.seerr.serviceConfig.StateDirectory == "seerr-custom"
    && seerr.systemd.services.seerr.environment.HOST == "127.0.0.1";
  readarrRetiredByDefault = !bare.nixstead.services.arr.readarr.enable;
  bareArrHasNoStorageOrMutations =
    bare.nixstead.services.arr.storage.root
    == null
    && bare.nixstead.services.arr.storage.torrents.root == null
    && !(bare.systemd.services ? nixstead-arr-directories)
    && !(bare.systemd.services ? nixstead-arr-reconcile);
  explicitStorageAndReconciliation =
    configured.nixstead.services.arr.qbittorrent.paths.savePath
    == "/data/torrents"
    && configured.systemd.services.sonarr.serviceConfig.UMask == "0002"
    && configured.systemd.services ? nixstead-arr-reconcile
    && configured.systemd.services ? nixstead-credential-sonarr
    && configured.nixstead.services.arr.credentials.enable;
  selectedExporterUsesCredentials =
    configured.services.prometheus.exporters.exportarr-sonarr.apiKeyFile
    == "/run/nixstead-credentials/sonarr/api-key"
    && configured.services.prometheus.exporters.exportarr-sonarr.environment.INTERFACE == "127.0.0.1"
    && !configured.services.prometheus.exporters.exportarr-radarr.enable;
  disabledServicesHaveNoExporters = !disabled.services.prometheus.exporters.exportarr-sonarr.enable;
  invalidStorageOverlap = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr = {
        sonarr.enable = true;
        storage = {
          root = "/data";
          libraries.tv = "/data/torrents/tv";
        };
      };
    }
  ] "download and library trees must be separate";
  unknownMountGuard = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr = {
        sonarr.enable = true;
        storage.root = "/mnt/missing/data";
      };
    }
  ] "require a declared fileSystems mount";
  conflictingIntegrationPaths = hasFailedAssertion [
    publicModules.arr
    {
      nixstead.services.arr = {
        sonarr.enable = true;
        qbittorrent = {
          enable = true;
          paths.savePath = "/other";
        };
        storage.root = "/data";
        integrations.enable = true;
      };
    }
  ] "Conflicting ARR integration paths";
  selectedFeatureClosure = builtins.isString configured.system.build.toplevel.drvPath;
}
