{
  config,
  host,
  lib,
  secretPlaceholder,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.dev;
in {
  config = lib.mkIf cfg.redis.enable {
    sops.secrets = {
      "devdb/redis/rootUser" = {};
      "devdb/redis/rootPassword" = {};
    };

    sops.templates."redis-users.acl" = {
      owner = "redis";
      content = ''
        user default off
        user ${secretPlaceholder "devdb/redis/rootUser"} on >${secretPlaceholder "devdb/redis/rootPassword"} ~* &* +@all
      '';
      restartUnits = ["redis.service"];
    };

    services.redis.servers."" = {
      enable = true;
      bind = serviceBindAddress "redis";
      port = config.nixstead.services.dev.redis.port;
      settings = {
        aclfile = config.sops.templates."redis-users.acl".path;
      };
    };

    # The native StateDirectory makes only /var/lib/redis writable. Hosts using
    # another native data directory also need that path in the unit sandbox.
    systemd.services.redis = {
      serviceConfig.ReadWritePaths = [config.services.redis.servers."".settings.dir];
      unitConfig.RequiresMountsFor = [config.services.redis.servers."".settings.dir];
    };
  };
}
