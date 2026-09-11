{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
  dataDir =
    if cfg.loki.paths.dataDir != null
    then cfg.loki.paths.dataDir
    else config.services.loki.dataDir;
in {
  config = lib.mkIf cfg.loki.enable {
    services.loki =
      {
        enable = true;
        configuration = {
          auth_enabled = false;

          server = {
            http_listen_address = serviceBindAddress "loki";
            # All components run in this process, even when HTTP is exposed.
            grpc_listen_address = "127.0.0.1";
            http_listen_port = config.nixstead.services.dev.loki.port;
          };

          common = {
            # Avoid advertising an auto-detected LAN address for loopback gRPC.
            instance_addr = "127.0.0.1";
            path_prefix = dataDir;
            replication_factor = 1;
            ring.kvstore.store = "inmemory";
          };

          frontend.address = "127.0.0.1";

          schema_config.configs = [
            {
              from = "2024-01-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];

          storage_config = {
            tsdb_shipper = {
              active_index_directory = "${dataDir}/tsdb-index";
              cache_location = "${dataDir}/tsdb-cache";
            };
            filesystem.directory = "${dataDir}/chunks";
          };
        };
      }
      // lib.optionalAttrs (cfg.loki.paths.dataDir != null) {
        dataDir = cfg.loki.paths.dataDir;
      };
  };
}
