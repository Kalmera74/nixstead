{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr.qbittorrent = {
      enable = true;
      port = 28107;
    };
    nixstead.services.arr.qbittorrent.paths = {
      savePath = "/srv/downloads/complete";
      tempPath = "/srv/downloads/incomplete";
    };
  };
  config = (mkSystem [selected]).config;
  custom = (mkSystem [selected {services.qbittorrent.profileDir = "/var/lib/qbittorrent-custom";}]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.qbittorrent = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
in
  (serviceContract {
    id = "qbittorrent";
    group = "arr";
    port = 28107;
    nativeEnabled = c: c.services.qbittorrent.enable;
  })
  // {
    nativePort = config.services.qbittorrent.webuiPort == 28107;
    nativeLoopback = config.services.qbittorrent.serverConfig.Preferences.WebUI.Address == "127.0.0.1";
    publicListener = public.services.qbittorrent.serverConfig.Preferences.WebUI.Address == "0.0.0.0";
    authenticatedLoopback = config.services.qbittorrent.serverConfig.Preferences.WebUI.LocalHostAuth;
    downloadPaths =
      config.services.qbittorrent.serverConfig.Preferences.Downloads
      == {
        SavePath = "/srv/downloads/complete";
        TempPath = "/srv/downloads/incomplete";
        TempPathEnabled = true;
      };
    mountDependencies = config.systemd.services.qbittorrent.unitConfig.RequiresMountsFor == ["/srv/downloads/complete" "/srv/downloads/incomplete"];
    runtimeCredentialDelivery = config.systemd.services.qbittorrent.serviceConfig.LoadCredential == ["username:/run/nixstead-credentials/qbittorrent/username" "password:/run/nixstead-credentials/qbittorrent/password"];
    backupApplicationProfile = config.nixstead.serviceRegistry.qbittorrent.backup.paths == ["/var/lib/qBittorrent"];
    backupFollowsNativeProfile = custom.nixstead.serviceRegistry.qbittorrent.backup.paths == ["/var/lib/qbittorrent-custom"];
    backupFollowsNativeGroup = config.nixstead.serviceRegistry.qbittorrent.backup.group == config.services.qbittorrent.group;
    storeCredentialRejected = rejects "Managed qBittorrent credentials" {nixstead.services.arr.qbittorrent.passwordFile = "/nix/store/forbidden-password";};
    noAutomaticStorageMutation = !config.nixstead.services.arr.storage.manageDirectories && !config.nixstead.services.arr.integrations.active;

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.qbittorrent.port = 70000;}]).config.nixstead.services.arr.qbittorrent.port).success;
  }
