{
  mkSystem,
  serviceContract,
  ...
}: let
  config =
    (mkSystem [
      {
        nixstead.services.productivity.paperless = {
          enable = true;
          paths = {
            dataDir = "/srv/paperless-data";
            mediaDir = "/srv/documents";
            consumeDir = "/srv/inbox";
          };
        };
      }
    ]).config;
in
  (serviceContract {
    id = "paperless";
    group = "productivity";
    port = 28982;
    nativeEnabled = c: c.services.paperless.enable;
  })
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.productivity.paperless.port = 70000;}]).config.nixstead.services.productivity.paperless.port).success;
    nativeDataDirectory = config.services.paperless.dataDir == "/srv/paperless-data";
    databaseDependency = config.services.postgresql.enable;
    separateStateCovered = config.nixstead.serviceRegistry.paperless.backup.paths == ["/srv/paperless-data" "/srv/documents" "/srv/inbox"];
    nativeDocumentPath = config.services.paperless.mediaDir == "/srv/documents";
    nativeInboxPath = config.services.paperless.consumptionDir == "/srv/inbox";
    singleSecretOwner = config.systemd.services.paperless-web.preStart == "" && config.systemd.services.paperless-secret-key.serviceConfig.User == config.services.paperless.user;
  }
