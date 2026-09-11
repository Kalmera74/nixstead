{
  config,
  host,
  lib,
  serviceBindAddress,
  ...
}: let
  cfg = config.nixstead.services.media;
  dataDir = cfg.audiobookshelf.paths.dataDir;
in {
  config = lib.mkIf cfg.audiobookshelf.enable {
    assertions = lib.optional (dataDir != null) {
      assertion = lib.hasPrefix "/var/lib/" dataDir && dataDir != "/var/lib/";
      message = "nixstead.services.media.audiobookshelf.paths.dataDir must be a directory below /var/lib when set.";
    };

    services.audiobookshelf =
      {
        enable = true;
        host = serviceBindAddress "audiobookshelf";
        port = config.nixstead.services.media.audiobookshelf.port;
      }
      // lib.optionalAttrs (dataDir != null) {
        dataDir = lib.removePrefix "/var/lib/" dataDir;
      };

    systemd.services.audiobookshelf.unitConfig.RequiresMountsFor = [
      config.systemd.services.audiobookshelf.serviceConfig.WorkingDirectory
    ];
  };
}
