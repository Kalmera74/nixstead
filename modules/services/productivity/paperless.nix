{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.productivity;
  paths = cfg.paperless.paths;
  dataDir =
    if paths.dataDir != null
    then paths.dataDir
    else config.services.paperless.dataDir;
  paperlessAllowedHosts = lib.unique (
    [cfg.paperless.domain "127.0.0.1" "localhost"]
    ++ lib.optional (cfg.paperless.ip != null) cfg.paperless.ip
    ++ lib.optional (host.network.tailscale != null) host.network.tailscale
  );
  paperlessMountPaths = lib.unique (lib.filter (path: path != null) [
    paths.dataDir
    paths.mediaDir
    paths.consumeDir
  ]);
in {
  config = lib.mkIf cfg.paperless.enable {
    services.paperless =
      {
        enable = true;
        address = serviceBindAddress "paperless";
        port = config.nixstead.services.productivity.paperless.port;
        database.createLocally = true;
        settings = {
          PAPERLESS_URL = "https://${config.nixstead.services.productivity.paperless.domain}";
          PAPERLESS_ALLOWED_HOSTS = lib.concatStringsSep "," paperlessAllowedHosts;
          PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://${config.nixstead.services.productivity.paperless.domain}";
        };
      }
      // lib.optionalAttrs (paths.dataDir != null) {
        inherit dataDir;
      }
      // lib.optionalAttrs (paths.mediaDir != null) {
        mediaDir = paths.mediaDir;
      }
      // lib.optionalAttrs (paths.consumeDir != null) {
        consumptionDir = paths.consumeDir;
      };

    users.users.paperless.extraGroups = [config.nixstead.host.groups.media];

    systemd.services = {
      # Celery Beat otherwise creates its sqlite-backed schedule database in
      # dataDir. Paperless data may live on CIFS/NFS, where sqlite locking is
      # unreliable and a scheduler crash also stops the bound web service.
      paperless-scheduler = {
        serviceConfig.ExecStart = lib.mkForce "${config.services.paperless.package}/bin/celery --app paperless beat --loglevel INFO --schedule /var/cache/paperless/celerybeat-schedule.db";
        unitConfig.RequiresMountsFor = paperlessMountPaths;
      };

      paperless-web.unitConfig.RequiresMountsFor = paperlessMountPaths;

      paperless-consumer.unitConfig.RequiresMountsFor = paperlessMountPaths;
      paperless-task-queue.unitConfig.RequiresMountsFor = paperlessMountPaths;
    };
  };
}
