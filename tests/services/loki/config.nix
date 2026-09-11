{
  lib,
  mkSystem,
  serviceContract,
  ...
}: let
  port = 23456;
  cfg =
    (mkSystem [
      {
        nixstead.services.dev.loki = {
          enable = true;
          inherit port;
          domain = "fixture-loki.example.test";
          paths.dataDir = "/srv/loki";
        };
      }
    ]).config;
in
  serviceContract {
    id = "loki";
    group = "dev";
    inherit port;
    nativeEnabled = c: c.services.loki.enable;
  }
  // {
    invalidPortRejected = !(builtins.tryEval (mkSystem [{nixstead.services.dev.loki.port = 70000;}]).config.nixstead.services.dev.loki.port).success;

    nativeListener = cfg.services.loki.configuration.server.http_listen_port == port && cfg.services.loki.configuration.server.http_listen_address == "127.0.0.1";
    internalGrpcPrivate = cfg.services.loki.configuration.server.grpc_listen_address == "127.0.0.1";
    nativeDataPath = cfg.services.loki.dataDir == "/srv/loki";
    indexesUseCustomPath = cfg.services.loki.configuration.storage_config.tsdb_shipper.active_index_directory == "/srv/loki/tsdb-index";
    chunksUseCustomPath = cfg.services.loki.configuration.storage_config.filesystem.directory == "/srv/loki/chunks";
    localStorageSchema = (builtins.head cfg.services.loki.configuration.schema_config.configs).object_store == "filesystem";
    disposableHistoryHasNoBackupClaim = cfg.nixstead.serviceRegistry.loki.backup == null;
  }
