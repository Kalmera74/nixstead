{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  settings = {
    enable = true;
    port = 29000;
    workerPort = 29001;
    metricsPort = 29300;
    workerMetricsPort = 29301;
    httpsPort = 29443;
    paths.dataDir = "/srv/identity";
  };
  c =
    (mkSystem [
      {
        nixstead.services.authentik = settings;
        services.postgresql.settings.port = 25434;
      }
    ]).config;
  exposed =
    (mkSystem [
      {
        nixstead.services.authentik = settings;
        nixstead.host.network.exposure.services.authentik = "public";
      }
    ]).config;
  disabled = (mkSystem []).config;
  server = c.systemd.services.authentik-server;
  worker = c.systemd.services.authentik-worker;
in
  (serviceContract {
    id = "authentik";
    port = 29000;
    nativeEnabled = c: c.systemd.services ? authentik-server;
  })
  // {
    databaseIsAutomatic = c.services.postgresql.enable && lib.elem "authentik-database-setup.service" server.requires && lib.elem "authentik-database-setup.service" worker.requires;
    customDatabasePortReachesSetupAndConsumers = lib.hasInfix "--port 25434" c.systemd.services.authentik-database-setup.script && lib.hasInfix "--port 25434" server.preStart && server.environment.AUTHENTIK_POSTGRESQL__PORT == "25434" && worker.environment.AUTHENTIK_POSTGRESQL__PORT == "25434" && c.nixstead.serviceRegistry.authentik.backup.databasePort == 25434;
    missingKeyRefusedBeforeApplication = lib.hasInfix "Missing or unreadable authentik signing key" server.preStart && lib.hasInfix "Missing or unreadable authentik signing key" worker.preStart;
    certificateDiscoveryIsOwnedAndArchived = server.environment.AUTHENTIK_CERT_DISCOVERY_DIR == "/srv/identity/certs" && worker.environment.AUTHENTIK_CERT_DISCOVERY_DIR == "/srv/identity/certs" && lib.elem "d /srv/identity/certs 0750 authentik authentik -" c.systemd.tmpfiles.rules;
    disabledRemovesWorkerAndDatabase = !(disabled.systemd.services ? authentik-worker) && !disabled.services.postgresql.enable;
    nativeServerListener = server.environment.AUTHENTIK_LISTEN__HTTP == "127.0.0.1:29000";
    internalListenersRemainLocal = exposed.systemd.services.authentik-worker.environment.AUTHENTIK_LISTEN__HTTP == "127.0.0.1:29001" && exposed.systemd.services.authentik-server.environment.AUTHENTIK_LISTEN__HTTPS == "127.0.0.1:29443" && server.environment.AUTHENTIK_LISTEN__METRICS == "127.0.0.1:29300" && worker.environment.AUTHENTIK_LISTEN__METRICS == "127.0.0.1:29301";
    onlyPublicHttpExposed = lib.elem 29000 exposed.networking.firewall.allowedTCPPorts && lib.all (p: !(lib.elem p exposed.networking.firewall.allowedTCPPorts)) [29001 29300 29301 29443];
    stateMountAndOwnership = server.serviceConfig.WorkingDirectory == "/srv/identity" && server.unitConfig.RequiresMountsFor == ["/srv/identity"] && c.users.users.authentik.home == "/srv/identity";
    secretFileOwnershipAndRotation = server.environment.AUTHENTIK_SECRET_KEY == "file://${c.sops.secrets."authentik/secretKey".path}" && c.sops.secrets."authentik/secretKey".owner == "authentik" && c.sops.secrets."authentik/secretKey".mode == "0400" && c.sops.secrets."authentik/secretKey".restartUnits == ["authentik-server.service" "authentik-worker.service"];
    combinedRecoveryWiring = c.nixstead.serviceRegistry.authentik.backup.paths == ["/srv/identity"] && c.nixstead.serviceRegistry.authentik.backup.databaseName == "authentik" && c.nixstead.serviceRegistry.authentik.backup.units == ["authentik-server.service" "authentik-worker.service"];
    invalidInternalPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.authentik.workerPort = 65536;}]).config.nixstead.services.authentik.workerPort).success;
  }
