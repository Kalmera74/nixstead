{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.media;
  configDir = toString config.services.seerr.configDir;
  stateDirectory = lib.removePrefix "/var/lib/" configDir;
  jellyfin = cfg.seerr.integrations.jellyfin;
  jellyfinSelected = cfg.seerr.integrations.enable && jellyfin.enable;
  jellyfinSecret = "homepage/${config.nixstead.serviceRegistry.jellyfin.homepage.widget.secrets.key}";
in {
  options.nixstead.services.media.seerr.integrations = {
    enable = lib.mkEnableOption "Seerr relationships after administrator bootstrap";
    jellyfin = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.seerr.enable && cfg.seerr.integrations.enable && cfg.jellyfin.enable;
        description = "Discover Jellyfin libraries and manage the internal connection after administrator bootstrap.";
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime Jellyfin-issued API key with library access. Null automatically uses the homepage/jellyfinApiKey SOPS entry, including when Homepage is disabled.";
      };
      libraryPolicy = lib.mkOption {
        type = lib.types.enum ["auto" "preserve" "movies-and-tv" "explicit"];
        default =
          if jellyfin.libraries != []
          then "explicit"
          else "auto";
        defaultText = lib.literalExpression ''if libraries != [] then "explicit" else "auto"'';
        description = ''
          auto preserves existing Seerr selections, selecting movie and TV libraries
          only when Seerr's library list is empty. preserve keeps all current choices
          and leaves newly discovered libraries disabled. movies-and-tv continually
          enables all movie and TV libraries. explicit enables the libraries list.
          No policy disables an existing selection; mixed libraries are never
          automatically selected. An existing list with all libraries disabled is
          preserved by auto. Discovery runs on every reconciliation.
        '';
      };
      libraries = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Explicit library IDs to enable in Seerr. Other libraries remain unchanged.";
      };
    };
    destinations = lib.genAttrs ["sonarr" "radarr"] (id: {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.seerr.enable && cfg.seerr.integrations.enable && (config.nixstead.services.arr.${id}.enable or false) && (cfg.seerr.integrations.destinations.${id}.existingServer != null || (cfg.seerr.integrations.destinations.${id}.qualityProfileId != null && cfg.seerr.integrations.destinations.${id}.rootFolder != null));
        description = "Ensure this explicitly selected Seerr request destination or existing connection.";
      };
      existingServer = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.unsigned;
              default = null;
              description = "Explicit existing Seerr server ID, including zero.";
            };
            name = lib.mkOption {
              type = lib.types.nullOr lib.types.nonEmptyStr;
              default = null;
              description = "Explicit existing Seerr server name. When both selectors are set, both must match initially.";
            };
          };
        });
        default = null;
        example = {};
        description = ''
          Explicitly manage only the connection fields of an existing server.
          An empty attribute set requires exactly one existing server on the
          first run. Its ID is then recorded in the ownership journal. Endpoints
          and API keys come from Nixstead; names, profiles, folders and request
          policy remain managed in Seerr. No server is created in this mode.
        '';
      };
      qualityProfileId = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Explicit ARR quality profile ID, validated through the API.";
      };
      rootFolder = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Explicit existing ARR root folder path.";
      };
      is4k = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use this request destination for 4K content.";
      };
      isDefault = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Select this default only when no other destination is already default.";
      };
      searchOnRequest = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow searching on newly approved requests.";
      };
    });
  };
  config = lib.mkIf cfg.seerr.enable {
    sops.secrets.${jellyfinSecret} = lib.mkIf (jellyfinSelected && jellyfin.apiKeyFile == null) {
      restartUnits = ["nixstead-arr-reconcile.service"];
    };
    services.seerr = {
      enable = true;
      port = cfg.seerr.port;
      stateRevision = 1;
      configDir = lib.mkDefault cfg.seerr.paths.configDir;
    };
    assertions = [
      {
        assertion = !cfg.seerr.integrations.enable || !(cfg.seerr.integrations.jellyfin.enable || lib.any (destination: destination.enable) (lib.attrValues cfg.seerr.integrations.destinations)) || (config.nixstead.services.arr.credentials.enable or false);
        message = "Seerr integration requires the ARR module and shared runtime credentials.";
      }
      {
        assertion =
          lib.hasPrefix "/var/lib/" configDir
          && stateDirectory != ""
          && stateDirectory != "private"
          && !lib.hasPrefix "private/" stateDirectory
          && lib.all (part: part != "" && part != "." && part != "..") (lib.splitString "/" stateDirectory);
        message = "Seerr configDir must be a normalized directory below /var/lib, outside /var/lib/private (systemd manages the private mapping).";
      }
    ];
    systemd.services.seerr = {
      environment.HOST = serviceBindAddress "seerr";
      # Native Seerr exits on SIGTERM without closing its SQLite connection,
      # leaving committed WAL pages behind. Once its writer has exited, fold
      # those pages into the database before any stopped-service snapshot.
      # Runtime external PostgreSQL settings retain their existing behavior.
      postStop = ''
        set -euo pipefail
        database=${lib.escapeShellArg "${configDir}/db/db.sqlite3"}
        if [[ "''${DB_TYPE:-sqlite}" != postgres && -s "$database" ]]; then
          checkpoint=$(${pkgs.sqlite}/bin/sqlite3 -batch "$database" 'PRAGMA wal_checkpoint(TRUNCATE);' 2>/dev/null) || {
            echo 'Seerr SQLite checkpoint failed.' >&2
            exit 1
          }
          if [[ "''${checkpoint%%|*}" != 0 ]]; then
            echo 'Seerr SQLite checkpoint remained busy.' >&2
            exit 1
          fi
        fi
      '';
      serviceConfig = {
        StateDirectory = lib.mkForce stateDirectory;
        StateDirectoryMode = "0700";
      };
    };
  };
}
