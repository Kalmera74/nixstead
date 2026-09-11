{
  config,
  lib,
  pkgs,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.arr;
  downloadPaths = cfg.qbittorrent.paths;
  downloadSettings =
    lib.optionalAttrs (downloadPaths.savePath != null) {
      SavePath = downloadPaths.savePath;
    }
    // lib.optionalAttrs (downloadPaths.tempPath != null) {
      TempPath = downloadPaths.tempPath;
      TempPathEnabled = true;
    };
  qbittorrentConfig = "${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf";
  python = pkgs.python3.withPackages (ps: [ps.pyyaml ps.configobj]);
in {
  config = lib.mkIf cfg.qbittorrent.enable {
    assertions =
      lib.mapAttrsToList (field: path: let
        name = "qbittorrent/${field}";
        secret = config.sops.secrets.${name} or null;
      in {
        assertion = path == null || (!lib.hasPrefix "/nix/store/" path && (cfg.credentials.documentFile != "/run/secrets/nixstead/credential-document" || (secret != null && secret.path == path && secret.key == name && secret.sopsFile == config.nixstead.secrets.sopsFile)));
        message = "Managed qBittorrent credentials must reference their canonical entries in the host SOPS document.";
      }) {
        username = cfg.qbittorrent.usernameFile;
        password = cfg.qbittorrent.passwordFile;
      };

    services.qbittorrent = {
      enable = true;
      group = config.nixstead.host.groups.media;
      webuiPort = cfg.qbittorrent.port;
      extraArgs = ["--confirm-legal-notice"];
      serverConfig = {
        LegalNotice.Accepted = true;

        # [BitTorrent] section
        BitTorrent = {
          "Session\\UseCategoryPathsInManualMode" = true;
          "Session\\SubcategoriesEnabled" = true;
          "Session\\DisableAutoTMMByDefault" = false;
        };

        # [Preferences] Section
        Preferences = {
          WebUI = {
            Address = serviceBindAddress "qbittorrent";
            LocalHostAuth = true;
          };
          Downloads = downloadSettings;
        };
      };
    };

    systemd.services.qbittorrent.serviceConfig.ExecStartPre = lib.mkAfter ["${python}/bin/python3 ${./credentials.py} --qbittorrent ${qbittorrentConfig}"];
    systemd.services.qbittorrent.serviceConfig.LoadCredential = ["username:/run/nixstead-credentials/qbittorrent/username" "password:/run/nixstead-credentials/qbittorrent/password"];
    systemd.services.qbittorrent.unitConfig.RequiresMountsFor = lib.filter (path: path != null) [
      downloadPaths.savePath
      downloadPaths.tempPath
    ];
  };
}
