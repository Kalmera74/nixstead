{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  selected = {
    nixstead.services.arr.shelfmark = {
      enable = true;
      port = 28109;
    };
    nixstead.services.arr.shelfmark.paths.ingestDir = "/srv/books/ingest";
  };
  config = (mkSystem [selected]).config;
  public = (mkSystem [selected {nixstead.host.network.exposure.services.shelfmark = "public";}]).config;
  rejects = message: override: lib.any (a: !a.assertion && lib.hasInfix message a.message) (mkSystem [selected override]).config.assertions;
  connected =
    (mkSystem [
      selected
      {
        nixstead.services.arr.shelfmark.integrations.enable = true;
        nixstead.services.arr.prowlarr = {
          enable = true;
          port = 28190;
        };
        nixstead.services.arr.qbittorrent = {
          enable = true;
          port = 28191;
        };
      }
    ]).config;
in
  (serviceContract {
    id = "shelfmark";
    group = "arr";
    port = 28109;
    nativeEnabled = c: c.services.shelfmark.enable;
    extra.nixstead.services.arr.shelfmark.paths.ingestDir = "/srv/books/ingest";
  })
  // {
    nativePort = config.services.shelfmark.environment.FLASK_PORT == "28109";
    nativeLoopback = config.services.shelfmark.environment.FLASK_HOST == "127.0.0.1";
    publicListener = public.services.shelfmark.environment.FLASK_HOST == "0.0.0.0";
    nativeIngest = config.services.shelfmark.environment.INGEST_DIR == "/srv/books/ingest";
    authenticationRequired = config.services.shelfmark.environment.AUTH_METHOD == "builtin";
    privateState = config.systemd.services.shelfmark.serviceConfig.StateDirectoryMode == "0700" && !config.systemd.services.shelfmark.serviceConfig.PrivateUsers;
    backupState = config.nixstead.serviceRegistry.shelfmark.backup.paths == ["/var/lib/shelfmark"];
    noImplicitIntegration = !(config.services.shelfmark.environment ? PROWLARR_URL);
    missingIngestRejected = rejects "explicitly selected ingest" {nixstead.services.arr.shelfmark.paths.ingestDir = lib.mkForce null;};
    missingProwlarrRejected = rejects "integration requires Prowlarr" {nixstead.services.arr.shelfmark.integrations.prowlarr = true;};
    missingQbittorrentRejected = rejects "integration requires qBittorrent" {nixstead.services.arr.shelfmark.integrations.qbittorrent = true;};
    dependencyPorts = connected.services.shelfmark.environment.PROWLARR_URL == "http://127.0.0.1:28190" && connected.services.shelfmark.environment.QBITTORRENT_URL == "http://127.0.0.1:28191";
    runtimeCredentials = connected.systemd.services.shelfmark.serviceConfig.LoadCredential == ["prowlarr:/run/nixstead-credentials/prowlarr/api-key" "username:/run/nixstead-credentials/qbittorrent/username" "password:/run/nixstead-credentials/qbittorrent/password"];
    noPlaintextCredentialEnvironment = !(connected.services.shelfmark.environment ? PROWLARR_API_KEY) && !(connected.services.shelfmark.environment ? QBITTORRENT_PASSWORD);

    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.arr.shelfmark.port = 70000;}]).config.nixstead.services.arr.shelfmark.port).success;
  }
