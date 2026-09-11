{
  config,
  lib,
  pkgs,
  serviceRegistry,
  ...
}: let
  cfg = config.nixstead.services.arr.credentials;
  arr = config.nixstead.services.arr;
  supported = lib.filterAttrs (_: entry: entry.api != null) serviceRegistry;
  enabled = lib.filterAttrs (id: _: cfg.enable && config.nixstead.serviceRegistry.${id}.enabled) supported;
  selected = enabled // lib.optionalAttrs arr.qbittorrent.enable {qbittorrent = serviceRegistry.qbittorrent;};
  python = pkgs.python3.withPackages (ps: [ps.pyyaml ps.configobj]);
  document = "/run/secrets/nixstead/credential-document";
  homepageEnabled = config.nixstead.services.homepage.enable or false;
  homepageConsumes = id: homepageEnabled && !lib.elem id (config.nixstead.services.homepage.disabledWidgets or []);
  swaps = id: arr.swaparr.enable && lib.elem id ["sonarr" "radarr" "lidarr"];
  consumers = id:
    lib.unique (
      ["${id}.service"]
      ++ lib.optional (homepageConsumes id) "homepage-dashboard.service"
      ++ lib.optional (swaps id) "docker-swaparr-${id}.service"
      ++ (cfg.consumers.${id} or [])
    );
  runtime = id: "/run/nixstead-credentials/${id}";
  publisher = id: "nixstead-credential-${id}";
  variables = id:
    if id == "seerr"
    then "API_KEY"
    else if id == "bazarr"
    then "DYNACONF_AUTH__APIKEY"
    else "${lib.toUpper id}__AUTH__APIKEY";
  fileFor = id: entry:
    pkgs.writeText "credential-source-${id}.json" (builtins.toJSON {
      service = id;
      document =
        if cfg.autoSync.enable
        then cfg.autoSync.documentFile
        else cfg.documentFile;
      keys =
        if id == "qbittorrent"
        then {
          username = {
            path = "qbittorrent/username";
            file =
              if cfg.autoSync.enable
              then null
              else arr.qbittorrent.usernameFile;
          };
          password = {
            path = "qbittorrent/password";
            file =
              if cfg.autoSync.enable
              then null
              else arr.qbittorrent.passwordFile;
          };
        }
        else {
          api-key = {
            path = entry.api.sopsSecret;
            file =
              if cfg.autoSync.enable
              then null
              else cfg.apiKeyFiles.${id};
          };
        };
      consumers = consumers id;
      outputs =
        map (key: {
          path = "${runtime id}/${key}";
          inherit key;
        }) (
          if id == "qbittorrent"
          then ["username" "password" "revision"]
          else ["api-key" "revision"]
        )
        ++ lib.optional (id != "qbittorrent" && id != "sabnzbd") {
          path = "${runtime id}/native.env";
          optional = true;
          environment.${variables id} = "api-key";
        }
        ++ lib.optional (id == "sabnzbd") {
          path = "${runtime id}/native.ini";
          ini = true;
        }
        ++ lib.optional (homepageConsumes id) {
          path = "${runtime id}/homepage.env";
          environment =
            if id == "qbittorrent"
            then {
              HOMEPAGE_VAR_QBITTORRENTUSERNAME = "username";
              HOMEPAGE_VAR_QBITTORRENTPASSWORD = "password";
            }
            else {"HOMEPAGE_VAR_${lib.toUpper entry.homepage.widget.secrets.key}" = "api-key";};
        }
        ++ lib.optional (swaps id) {
          path = "${runtime id}/swaparr.env";
          key = "api-key";
          # Docker env files retain quotes literally; API keys need no escaping.
          prefix = "APIKEY=";
        };
    });
in {
  imports = [./credential_enrollment.nix];
  options.nixstead.services.arr.credentials = {
    enable = (lib.mkEnableOption "canonical SOPS credentials for ARR, Seerr and their consumers") // {default = homepageEnabled;};
    documentFile = lib.mkOption {
      type = lib.types.str;
      internal = true;
      default = document;
      description = "Root-only decrypted SOPS document. Replace only at the test boundary.";
    };
    apiKeyFiles = lib.mapAttrs (_: _:
      lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional declared SOPS secret path overriding the canonical service API-key entry.";
      })
    supported;
    consumers = lib.genAttrs (lib.attrNames supported ++ ["qbittorrent"]) (_:
      lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        internal = true;
        description = "Additional units receiving a deployed credential and restarted when it changes.";
      });
  };
  config = lib.mkIf (selected != {}) {
    # Decrypt once for the root broker. Optional entries permit application
    # bootstrap; only each service's selected values reach its consumers.
    sops.secrets."nixstead/credential-document" = lib.mkIf (!cfg.autoSync.enable && cfg.documentFile == document && config.nixstead.secrets.enable) {
      key = "";
      mode = "0400";
      restartUnits = map (id: "${publisher id}-refresh.service") (lib.attrNames selected);
    };
    assertions =
      lib.mapAttrsToList (id: path: let
        name = supported.${id}.api.sopsSecret;
        secret = config.sops.secrets.${name} or null;
      in {
        assertion = path == null || (lib.hasPrefix "/" path && !lib.hasPrefix "/nix/store/" path && (cfg.documentFile != document || (secret != null && secret.path == path && secret.key == name && secret.sopsFile == config.nixstead.secrets.sopsFile)));
        message = "Managed API key overrides must reference their canonical entry in the host SOPS document.";
      })
      cfg.apiKeyFiles;
    systemd.services = lib.mkMerge (lib.mapAttrsToList (id: entry:
      lib.mkMerge [
        {
          ${publisher id} = {
            description = "Deliver canonical SOPS ${entry.name} credentials";
            after = ["sops-install-secrets.service"] ++ lib.optional cfg.autoSync.enable "nixstead-credentials-sync.service";
            requires = lib.optional cfg.autoSync.enable "nixstead-credentials-sync.service";
            wantedBy = ["multi-user.target"];
            restartTriggers = [(fileFor id entry)];
            path = [pkgs.systemd];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RuntimeDirectory = "nixstead-credentials/${id}";
              RuntimeDirectoryMode = "0700";
              RuntimeDirectoryPreserve = true;
              UMask = "0077";
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              TimeoutStartSec = 30;
              ExecStart = "${python}/bin/python3 ${./credentials.py} ${fileFor id entry}";
            };
          };
          "${publisher id}-refresh" = {
            description = "Refresh deployed ${entry.name} credentials";
            after = ["${publisher id}.service"];
            requires = ["${publisher id}.service"];
            path = [pkgs.systemd];
            serviceConfig = {
              Type = "oneshot";
              UMask = "0077";
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
              ReadWritePaths = [(runtime id)];
              ExecStart = "${python}/bin/python3 ${./credentials.py} ${fileFor id entry}";
            };
          };
        }
        (lib.optionalAttrs (id != "qbittorrent" && id != "sabnzbd") {
          ${id}.serviceConfig.EnvironmentFile = ["${runtime id}/native.env"];
        })
        (lib.genAttrs (map (unit: lib.removeSuffix ".service" unit) (consumers id)) (unit: {
          after = ["${publisher id}.service"];
          requires = ["${publisher id}.service"];
          unitConfig.ConditionPathExists = lib.optional (lib.hasPrefix "prometheus-" unit || lib.hasPrefix "docker-swaparr-" unit) "${runtime id}/ready";
        }))
      ])
    selected);
    systemd.timers = lib.mkIf (!cfg.autoSync.enable) (lib.mapAttrs' (id: _:
      lib.nameValuePair (publisher id) {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "1m";
          OnUnitInactiveSec = "1m";
          Unit = "${publisher id}-refresh.service";
        };
      })
    selected);
  };
}
