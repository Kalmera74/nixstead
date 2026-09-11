{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;

  serviceRegistry = import ../services/registry.nix;
  runtimePathOption = default: description:
    mkOption {
      type = types.path;
      inherit default description;
    };
  optionalRuntimePathOption = description:
    mkOption {
      type = types.nullOr types.path;
      default = null;
      inherit description;
    };
  ociImageReferenceType = types.strMatching (import ../services/registry/lib.nix).ociImageReferencePattern;
  ociImageOption = default: description:
    mkOption {
      type = ociImageReferenceType;
      inherit default description;
    };
  ociImagesOption = images: description:
    mkOption {
      type = types.submodule {
        options =
          lib.mapAttrs (
            name: default:
              ociImageOption default "Digest-pinned OCI image used by the ${name} container."
          )
          images;
      };
      default = {};
      inherit description;
    };
  exposureType = types.enum ["loopback" "lan" "tailnet" "public"];
  interfaceNameType = types.strMatching "[a-zA-Z0-9_.:+-]+";
  sourceNetworkType = types.strMatching "[0-9a-fA-F:.]+/[0-9]+";

  exposureSelectorType = types.submodule {
    options = {
      interfaces = mkOption {
        type = types.listOf interfaceNameType;
        default = [];
        description = "Interfaces on which this exposure class is reachable.";
      };

      sourceNetworks = mkOption {
        type = types.listOf sourceNetworkType;
        default = [];
        example = ["192.168.1.0/24"];
        description = "IPv4 or IPv6 source networks allowed to use this exposure class.";
      };
    };
  };

  exposureServiceOptions = lib.mapAttrs (_: entry:
    mkOption {
      type = types.nullOr exposureType;
      default = null;
      description = "Optional exposure override for ${entry.name}.";
    })
  (lib.filterAttrs (_: entry: entry.exposure != null) serviceRegistry);

  serviceOption = {
    name,
    enable ? false,
    domain ? null,
    ip ? config.nixstead.host.network.lan,
    port ? null,
    pathOptions ? {},
    extraOptions ? {},
  }:
    mkOption {
      type = types.submodule {
        options =
          {
            enable = mkOption {
              type = types.bool;
              default = enable;
              description = "Whether the service is enabled.";
            };

            domain = mkOption {
              type = types.nullOr types.str;
              default = domain;
              description = "DNS name used to reach the service.";
            };

            ip = mkOption {
              type = types.nullOr types.str;
              default = ip;
              description = "IP address used to reach the service.";
            };

            port = mkOption {
              type = types.nullOr types.port;
              default = port;
              description = "Port used to reach the service.";
            };
          }
          // lib.optionalAttrs (pathOptions != {}) {
            paths = mkOption {
              type = types.submodule {options = pathOptions;};
              default = {};
              description = "Typed runtime filesystem paths used by the service.";
            };
          }
          // extraOptions;
      };
      default = {};
      description = "Configuration for the ${name} service.";
    };

  serviceOptionFromRegistry = id: overrides: let
    entry = serviceRegistry.${id};
    defaults = entry.defaults;
    defaultDomain =
      if defaults ? subdomain
      then "${defaults.subdomain}.${config.nixstead.host.network.baseDomain}"
      else defaults.domain or null;
    defaultIp =
      if defaults ? hostNetwork
      then lib.attrByPath ["network" defaults.hostNetwork] null config.nixstead.host
      else config.nixstead.host.network.lan;
  in
    serviceOption (
      {
        inherit (entry) name;
        enable = false;
        domain = defaultDomain;
        ip = defaultIp;
        port = defaults.port or null;
      }
      // overrides
    );

  addressOption = mkOption {
    type = types.nullOr types.str;
    default = null;
  };

  machineType = types.submodule {
    options = {
      hostName = mkOption {
        type = types.str;
        default = "nixos";
        description = "The machine hostname.";
      };

      configurationName = mkOption {
        type = types.str;
        default = "nixos";
        description = "The flake configuration used to rebuild this machine.";
      };

      repositoryPath = mkOption {
        type = types.str;
        default = "/etc/nixos";
        description = "Path to this configuration repository on the machine.";
      };

      groups = mkOption {
        type = types.submodule {
          options = {
            media = mkOption {
              type = types.str;
              default = "media";
              description = "Group used for shared media access.";
            };
            mediaGid = mkOption {
              type = types.ints.positive;
              default = config.nixstead.host.user.uid;
              description = "Numeric GID used for shared media access and passed to containers that require it.";
            };
          };
        };
        default = {};
      };

      network = mkOption {
        type = types.submodule {
          options = {
            baseDomain = mkOption {
              type = types.strMatching "([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])(\\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]))*";
              default = "home.arpa";
              example = "lab.example.com";
              description = "Base DNS domain appended to registry service subdomains unless a service domain is overridden explicitly.";
            };

            lan = addressOption;
            tailscale = addressOption;
            router = addressOption;
            switch = addressOption;
            pihole = addressOption;
            proxmox = addressOption;
            truenas = addressOption;

            exposure = mkOption {
              type = types.submodule {
                options = {
                  default = mkOption {
                    type = types.nullOr exposureType;
                    default = null;
                    description = "Optional host-wide override for registry-managed service exposure defaults.";
                  };

                  services = mkOption {
                    type = types.submodule {options = exposureServiceOptions;};
                    default = {};
                    description = "Per-service exposure overrides.";
                  };

                  lan = mkOption {
                    type = exposureSelectorType;
                    default = {};
                    description = "Interface and source-network selectors for LAN exposure.";
                  };

                  tailnet = mkOption {
                    type = exposureSelectorType;
                    default.interfaces = ["tailscale0"];
                    description = "Interface and source-network selectors for tailnet exposure.";
                  };
                };
              };
              default = {};
              description = "Network exposure policy for registry-managed services.";
            };
          };
        };
        default = {};
      };

      ports = mkOption {
        type = types.submodule {
          options = {
            ssh = mkOption {
              type = types.port;
              default = 22;
            };
            http = mkOption {
              type = types.port;
              default = 80;
            };
            https = mkOption {
              type = types.port;
              default = 443;
            };
          };
        };
        default = {};
      };

      ssh = mkOption {
        type = types.submodule {
          options = {
            authorizedKeys = mkOption {
              type = types.listOf types.str;
              default = [];
              example = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... admin@example"];
              description = "SSH public keys authorized for the managed host user.";
            };
            passwordAuthentication = mkOption {
              type = types.bool;
              default = true;
              description = "Whether SSH password and keyboard-interactive authentication are allowed.";
            };
            rootLogin = mkOption {
              type = types.enum ["yes" "without-password" "prohibit-password" "forced-commands-only" "no"];
              default = "no";
              description = "OpenSSH PermitRootLogin policy.";
            };
          };
        };
        default = {};
        description = "SSH authentication policy for this host.";
      };

      hardware = mkOption {
        type = types.submodule {
          options = {
            audio.enable = mkOption {
              type = types.bool;
              default = false;
            };
            bluetooth.enable = mkOption {
              type = types.bool;
              default = false;
            };
            enableAllFirmware = mkOption {
              type = types.bool;
              default = false;
            };

            swap = mkOption {
              type = types.submodule {
                options = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                  };
                  device = mkOption {
                    type = types.str;
                    default = "/swapfile";
                  };
                  sizeMiB = mkOption {
                    type = types.ints.unsigned;
                    default = 0;
                  };
                };
              };
              default = {};
            };

            gpu.acceleration = mkOption {
              type = types.enum ["none" "cuda" "rocm"];
              default = "none";
            };
          };
        };
        default = {};
      };

      locale = mkOption {
        type = types.submodule {
          options = {
            timeZone = mkOption {
              type = types.str;
              default = "UTC";
            };
            defaultLocale = mkOption {
              type = types.str;
              default = "en_US.UTF-8";
            };
            extraLocaleSettings = mkOption {
              type = types.attrsOf types.str;
              default = {};
            };
            consoleKeyMap = mkOption {
              type = types.str;
              default = "us";
            };
          };
        };
        default = {};
      };

      user = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
            };
            name = mkOption {
              type = types.str;
              default = "nixos";
            };
            description = mkOption {
              type = types.str;
              default = "NixOS user";
            };
            uid = mkOption {
              type = types.ints.unsigned;
              default = 1000;
            };
            extraGroups = mkOption {
              type = types.listOf types.str;
              default = ["networkmanager" "wheel"];
            };
            generatedFilesDirectory = mkOption {
              type = types.strMatching "[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*";
              default = ".local/share/nixstead";
              description = "Directory relative to the user's home for generated user-owned files.";
            };
          };
        };
        default = {};
      };
    };
  };

  servicesConfig = config.nixstead.services or {};
  resolveEntry = id: entry: let
    settings = lib.attrByPath entry.optionPath {} servicesConfig;
    enabled = lib.attrByPath entry.enablePath false servicesConfig;
    exposureOverride = config.nixstead.host.network.exposure.services.${id} or null;
    resolvedBackup =
      if entry.backup == null
      then null
      else let
        configuredPaths = lib.filter (path: path != null) (map (
            optionPath: lib.attrByPath optionPath null settings
          )
          ([entry.backup.pathOption or ["paths" "dataDir"]] ++ (entry.backup.extraPathOptions or [])));
        nativePathFallback = let
          configured = entry.backup.defaultPath or (lib.attrByPath (entry.backup.pathOption or ["paths" "dataDir"]) null settings);
        in
          if configured == null
          then "/var/lib/${entry.backup.directory}"
          else configured;
        selectedNativePath =
          if entry.backup ? nativePathOption
          then
            if lib.attrByPath (entry.backup.nativePathOption ++ ["isDefined"]) null options == false
            then nativePathFallback
            else lib.attrByPath entry.backup.nativePathOption nativePathFallback config
          else null;
        primaryPaths =
          if entry.backup ? nativePathOption
          then [
            ((
                if selectedNativePath == null
                then nativePathFallback
                else selectedNativePath
              )
              + (entry.backup.nativePathSuffix or ""))
          ]
          else if configuredPaths != []
          then configuredPaths
          else ["/var/lib/${entry.backup.directory}"];
        extraPaths = map (optionPath: lib.attrByPath optionPath null config) (entry.backup.extraNativePathOptions or []);
        nativeSQLiteFiles =
          if entry.backup ? requiredFilesFromNativeSQLite
          then let
            requirement = entry.backup.requiredFilesFromNativeSQLite;
            databaseType =
              if requirement ? typeOption
              then lib.attrByPath requirement.typeOption null config
              else "sqlite3";
            configuredDatabasePath = lib.attrByPath requirement.pathOption null config;
            databasePath =
              if configuredDatabasePath == null
              then null
              else configuredDatabasePath + (requirement.pathSuffix or "");
            primary = lib.head primaryPaths;
          in
            lib.optional (databaseType == "sqlite3" && databasePath != null && lib.hasPrefix "${primary}/" databasePath)
            (lib.removePrefix "${primary}/" databasePath)
          else [];
        # Keep the primary archive slot stable. Separate native directories need
        # their own slot only when the primary snapshot does not already cover them.
        paths = lib.unique (primaryPaths
          ++ lib.filter (path:
            path != null && !lib.any (primary: path == primary || lib.hasPrefix "${primary}/" path) primaryPaths)
          extraPaths);
      in
        entry.backup
        // {
          inherit paths;
          requiredFiles =
            (entry.backup.requiredFiles or [])
            ++ nativeSQLiteFiles
            ++ lib.concatMap (requirement:
              lib.optionals (lib.attrByPath requirement.option null settings == null) requirement.files)
            (entry.backup.requiredFilesWhenNull or [])
            ++ lib.concatMap (requirement:
              lib.optionals
              (lib.all (guard: lib.attrByPath guard.option null config == guard.value)
                ([requirement] ++ (requirement.extraMatches or [])))
              requirement.files)
            (entry.backup.requiredFilesWhenNativeEquals or []);
          rdb =
            if entry.backup ? rdbServerOption
            then let
              server = lib.attrByPath entry.backup.rdbServerOption {} config;
              # Native settings can override high-level persistence options.
              # Match Redis's case-insensitive, last-value setting resolution.
              persistence =
                lib.foldlAttrs (all: name: value:
                  all // {${lib.toLower name} = value;}) {} (server.settings or {});
              package = lib.getAttrFromPath entry.backup.rdbPackageOption config;
            in
              if lib.elem (persistence.save or []) [[] "" ''""''] || lib.elem (persistence.appendonly or false) [true "yes"]
              then null
              else {
                file = persistence.dbfilename;
                checker = "${package}/bin/redis-check-rdb";
              }
            else null;
          mongodbDirectoryCheck =
            if enabled && entry.backup ? mongodbPackageOption
            then {
              executable = "${lib.getAttrFromPath entry.backup.mongodbPackageOption config}/bin/mongod";
              arguments = ["--auth" "--bind_ip" "127.0.0.1" "--port" "27017" "--nounixsocket" "--wiredTigerCacheSizeGB" "0.25"];
              ip = "${pkgs.iproute2}/bin/ip";
              timeoutSeconds = 45;
            }
            else null;
          databaseName =
            if entry.backup ? databaseNameOption
            then lib.attrByPath entry.backup.databaseNameOption entry.backup.databaseName config
            else entry.backup.databaseName or null;
          databasePort =
            if entry.backup ? databasePortOption
            then lib.attrByPath entry.backup.databasePortOption (entry.backup.databasePort or 5432) config
            else entry.backup.databasePort or null;
          owner = let
            nativeOwner =
              if entry.backup ? ownerOption
              then lib.attrByPath entry.backup.ownerOption entry.backup.owner config
              else entry.backup.owner;
            # Some native modules use null to request a DynamicUser with a
            # stable service identity. Keep registry metadata as the restore
            # identity for that default profile.
            selected =
              if nativeOwner == null
              then entry.backup.owner
              else nativeOwner;
          in
            toString (
              if entry.backup ? ownerFallbackOption && !(builtins.hasAttr (toString selected) config.users.users)
              then lib.getAttrFromPath entry.backup.ownerFallbackOption config
              else selected
            );
          group = let
            nativeGroup =
              if entry.backup ? groupOption
              then lib.attrByPath entry.backup.groupOption entry.backup.group config
              else entry.backup.group;
          in
            toString (
              if nativeGroup == null
              then entry.backup.group
              else nativeGroup
            );
          path = lib.head paths;
        };
  in
    entry
    // {
      inherit enabled;
      backup = resolvedBackup;
      credentialSopsFile =
        if entry.api != null || id == "qbittorrent"
        then config.nixstead.services.arr.credentials.autoSync.sourceFile or null
        else null;
      api =
        if entry.api == null
        then null
        else
          entry.api
          // {
            stateFile = "${lib.attrByPath entry.api.nativePathOption "/var/lib/${id}" config}/${entry.api.suffix}";
          };
      exposure =
        if exposureOverride != null
        then exposureOverride
        else if config.nixstead.host.network.exposure.default != null && entry.exposure != null
        then config.nixstead.host.network.exposure.default
        else entry.exposure;
      settings =
        if builtins.isAttrs settings
        then settings
        else {};
    };

  resolvedRegistry = lib.mapAttrs resolveEntry serviceRegistry;
  enabledProxies = lib.filterAttrs (_: entry: entry.enabled && entry.proxy != null) resolvedRegistry;
  enabledDnsDomains = map (entry: entry.settings.domain) (
    lib.attrValues (lib.filterAttrs (_: entry: entry.enabled && entry.dns) resolvedRegistry)
  );
  backupDirectories = map (entry: entry.backup.directory) (
    lib.attrValues (lib.filterAttrs (_: entry: entry.backup != null) resolvedRegistry)
  );
  enabledLanServices = lib.attrValues (lib.filterAttrs (
      _: entry: entry.enabled && entry.exposure == "lan"
    )
    resolvedRegistry);
  enabledTailnetServices = lib.attrValues (lib.filterAttrs (
      _: entry: entry.enabled && entry.exposure == "tailnet"
    )
    resolvedRegistry);
  enabledPublishedLanServices =
    lib.filter (
      entry: entry.containerPublished
    )
    enabledLanServices;
  enabledPublishedTailnetServices =
    lib.filter (
      entry: entry.containerPublished
    )
    enabledTailnetServices;

  enabledLocalListeners =
    lib.filterAttrs (
      _: entry: entry.enabled && entry.local
    )
    resolvedRegistry;
  listenerClaimsFor = protocol: id: entry: let
    listeners = entry.listeners;
    capitalizedProtocol =
      if protocol == "tcp"
      then "Tcp"
      else "Udp";
    settingsNames = listeners."settings${capitalizedProtocol}Ports" or [];
    hostNames = listeners."host${capitalizedProtocol}Ports" or [];
    staticPorts = listeners."${protocol}Ports" or [];
    settingsClaims =
      map (name: {
        service = id;
        source = "nixstead.services.${lib.concatStringsSep "." entry.optionPath}.${name}";
        port = lib.attrByPath [name] null entry.settings;
      })
      settingsNames;
    hostClaims =
      map (name: {
        service = id;
        source = "nixstead.host.ports.${name}";
        port = config.nixstead.host.ports.${name};
      })
      hostNames;
    staticClaims =
      map (port: {
        service = id;
        source = "registry static port";
        inherit port;
      })
      staticPorts;
  in
    settingsClaims ++ hostClaims ++ staticClaims;
  listenerClaims = protocol:
    lib.concatLists (lib.mapAttrsToList (listenerClaimsFor protocol) enabledLocalListeners);
  tcpListenerClaims = listenerClaims "tcp";
  udpListenerClaims = listenerClaims "udp";
  missingListenerClaims = lib.filter (claim: claim.port == null) (tcpListenerClaims ++ udpListenerClaims);
  collisionPortsFor = claims: let
    ports = lib.unique (map (claim: claim.port) (lib.filter (claim: claim.port != null) claims));
  in
    lib.filter (
      port: lib.length (lib.filter (claim: claim.port == port) claims) > 1
    )
    ports;
  tcpCollisionPorts = collisionPortsFor tcpListenerClaims;
  udpCollisionPorts = collisionPortsFor udpListenerClaims;
  collisionMessage = protocol: claims: ports:
    lib.concatMapStringsSep "; " (
      port: let
        owners = map (claim: "${claim.service} (${claim.source})") (
          lib.filter (claim: claim.port == port) claims
        );
      in "${protocol}/${toString port}: ${lib.concatStringsSep ", " owners}"
    )
    ports;

  serviceBindAddress = id:
    if resolvedRegistry.${id}.exposure == "loopback"
    then "127.0.0.1"
    else "0.0.0.0";
  servicePublishAddress = id: let
    exposure = resolvedRegistry.${id}.exposure;
  in
    if exposure == "loopback"
    then "127.0.0.1"
    else if exposure == "lan"
    then
      if config.nixstead.host.network.lan != null
      then config.nixstead.host.network.lan
      else "127.0.0.1"
    else if exposure == "tailnet"
    then
      if config.nixstead.host.network.tailscale != null
      then config.nixstead.host.network.tailscale
      else "127.0.0.1"
    else "0.0.0.0";
  enabledUnfreeServicePackages =
    lib.optionals resolvedRegistry.sabnzbd.enabled ["unrar"]
    ++ lib.optionals resolvedRegistry.n8n.enabled ["n8n"]
    ++ lib.optionals resolvedRegistry.mongodb.enabled ["mongodb-ce"]
    ++ lib.optionals resolvedRegistry.openwebui.enabled ["open-webui"]
    ++ lib.optionals (resolvedRegistry.tdarr.enabled || resolvedRegistry.tdarr-node.enabled) ["tdarr-node" "tdarr-server"];
in {
  options = {
    nixstead.host = mkOption {
      type = machineType;
      default = {};
      description = "Typed host-specific machine configuration.";
    };

    nixstead.serviceRegistry = mkOption {
      type = types.attrsOf types.anything;
      readOnly = true;
      description = "Resolved service metadata used by integrations and maintenance tools.";
    };
  };

  config = {
    nixstead.serviceRegistry = resolvedRegistry;

    # Service modules may require a small number of explicitly known unfree
    # packages without granting every importing host a global unfree policy.
    nixpkgs.config.allowUnfreePredicate =
      lib.mkDefault (package:
        builtins.elem (lib.getName package) enabledUnfreeServicePackages);

    _module.args = {
      host = config.nixstead.host;
      inherit ociImageOption ociImageReferenceType ociImagesOption optionalRuntimePathOption runtimePathOption serviceBindAddress serviceOption serviceOptionFromRegistry servicePublishAddress serviceRegistry;
    };

    assertions = [
      {
        assertion = !config.nixstead.host.hardware.swap.enable || config.nixstead.host.hardware.swap.sizeMiB > 0;
        message = "nixstead.host.hardware.swap.sizeMiB must be greater than zero when swap is enabled.";
      }
      {
        assertion = config.nixstead.host.ssh.authorizedKeys == [] || config.nixstead.host.user.enable;
        message = "nixstead.host.ssh.authorizedKeys requires nixstead.host.user.enable.";
      }
      {
        assertion =
          config.nixstead.host.user.generatedFilesDirectory
          != "."
          && !lib.elem ".." (lib.splitString "/" config.nixstead.host.user.generatedFilesDirectory);
        message = "nixstead.host.user.generatedFilesDirectory must be a non-empty relative subdirectory without '..' components.";
      }
      {
        assertion = lib.all (
          entry:
            entry.settings ? domain
            && entry.settings.domain != null
            && entry.settings ? port
            && entry.settings.port != null
            && (entry.proxy.target != "service" || (entry.settings ? ip && entry.settings.ip != null))
        ) (lib.attrValues enabledProxies);
        message = "Every enabled registry proxy requires a domain, port, and reachable target IP.";
      }
      {
        assertion = lib.length enabledDnsDomains == lib.length (lib.unique enabledDnsDomains);
        message = "Enabled service-registry DNS domains must be unique.";
      }
      {
        assertion = lib.length backupDirectories == lib.length (lib.unique backupDirectories);
        message = "Service-registry backup directories must be unique.";
      }
      {
        assertion =
          enabledLanServices
          == []
          || config.nixstead.host.network.exposure.lan.interfaces != []
          || config.nixstead.host.network.exposure.lan.sourceNetworks != [];
        message = "LAN-exposed services require nixstead.host.network.exposure.lan.interfaces or sourceNetworks.";
      }
      {
        assertion =
          enabledTailnetServices
          == []
          || config.nixstead.host.network.exposure.tailnet.interfaces != []
          || config.nixstead.host.network.exposure.tailnet.sourceNetworks != [];
        message = "Tailnet-exposed services require nixstead.host.network.exposure.tailnet.interfaces or sourceNetworks.";
      }
      {
        assertion = enabledPublishedLanServices == [] || config.nixstead.host.network.lan != null;
        message = "LAN-exposed container ports require nixstead.host.network.lan so they do not bypass the host firewall.";
      }
      {
        assertion = enabledPublishedTailnetServices == [] || config.nixstead.host.network.tailscale != null;
        message = "Tailnet-exposed container ports require nixstead.host.network.tailscale so they do not bypass the host firewall.";
      }
      {
        assertion = missingListenerClaims == [];
        message = "Every enabled local service listener must resolve to a non-null port.";
      }
      {
        assertion = tcpCollisionPorts == [];
        message = "Enabled services have TCP listener collisions: ${collisionMessage "tcp" tcpListenerClaims tcpCollisionPorts}";
      }
      {
        assertion = udpCollisionPorts == [];
        message = "Enabled services have UDP listener collisions: ${collisionMessage "udp" udpListenerClaims udpCollisionPorts}";
      }
    ];
  };
}
