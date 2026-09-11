{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  arr = config.nixstead.services.arr;
  cfg = arr.shelfmark;
  prowlarr = cfg.integrations.prowlarr;
  qbittorrent = cfg.integrations.qbittorrent;
  sources =
    lib.optionalAttrs prowlarr {PROWLARR_API_KEY = "prowlarr";}
    // lib.optionalAttrs qbittorrent {
      QBITTORRENT_USERNAME = "username";
      QBITTORRENT_PASSWORD = "password";
    };
  specification = pkgs.writeText "shelfmark-runtime-environment.json" (builtins.toJSON sources);
in {
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.paths.ingestDir != null;
        message = "Shelfmark requires an explicitly selected ingest destination.";
      }
      {
        assertion = !prowlarr || arr.prowlarr.enable;
        message = "Shelfmark Prowlarr integration requires Prowlarr.";
      }
      {
        assertion = !qbittorrent || arr.qbittorrent.enable;
        message = "Shelfmark qBittorrent integration requires qBittorrent.";
      }
    ];
    services.shelfmark = {
      enable = true;
      environment =
        {
          FLASK_HOST = serviceBindAddress "shelfmark";
          FLASK_PORT = cfg.port;
          AUTH_METHOD = "builtin";
          INGEST_DIR = cfg.paths.ingestDir;
        }
        // lib.optionalAttrs prowlarr {
          PROWLARR_ENABLED = "true";
          PROWLARR_URL = "http://127.0.0.1:${toString arr.prowlarr.port}";
        }
        // lib.optionalAttrs qbittorrent {
          PROWLARR_TORRENT_CLIENT = "qbittorrent";
          QBITTORRENT_URL = "http://127.0.0.1:${toString arr.qbittorrent.port}";
        };
    };
    nixstead.services.arr.credentials = {
      enable = lib.mkIf prowlarr (lib.mkDefault true);
      consumers.prowlarr = lib.optional prowlarr "shelfmark.service";
      consumers.qbittorrent = lib.optional qbittorrent "shelfmark.service";
    };
    systemd.services.shelfmark = {
      after = lib.optional qbittorrent "qbittorrent.service";
      wants = lib.optional qbittorrent "qbittorrent.service";
      restartTriggers = [specification];
      serviceConfig = {
        SupplementaryGroups = [config.nixstead.host.groups.media];
        # Map the actual shared media group for access to mounted libraries.
        PrivateUsers = lib.mkForce false;
        StateDirectoryMode = "0700";
        UMask = lib.mkForce "0002";
        RuntimeDirectory = "nixstead-shelfmark";
        RuntimeDirectoryMode = "0700";
        EnvironmentFile = ["-/run/nixstead-shelfmark/environment"];
        ExecStartPre = lib.optional (sources != {}) "${pkgs.python3}/bin/python3 ${./runtime_environment.py} ${specification} /run/nixstead-shelfmark/environment";
        LoadCredential =
          lib.optional prowlarr "prowlarr:/run/nixstead-credentials/prowlarr/api-key"
          ++ lib.optionals qbittorrent [
            "username:/run/nixstead-credentials/qbittorrent/username"
            "password:/run/nixstead-credentials/qbittorrent/password"
          ];
      };
    };
  };
}
