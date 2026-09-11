{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.services.nas;
  dataDisks = lib.listToAttrs (
    map (disk: {
      name = disk.name;
      value = "${disk.mountPoint}/";
    })
    cfg.disks.data
  );
  parityFiles = map (disk: "${disk.mountPoint}/snapraid.parity") cfg.disks.parity;
  contentFiles =
    ["/var/lib/snapraid/snapraid.content"]
    ++ map (disk: "${disk.mountPoint}/snapraid.content") (cfg.disks.data ++ cfg.disks.parity);
  diskMounts = map (disk: disk.mountPoint) (cfg.disks.data ++ cfg.disks.parity);
  maintenanceMounts = {
    unitConfig = {
      RequiresMountsFor = diskMounts;
      ConditionPathIsMountPoint = diskMounts;
    };
    serviceConfig.StateDirectory = "snapraid";
  };
in {
  config = lib.mkIf (cfg.snapraid.enable && cfg.disks.data != [] && cfg.disks.parity != []) {
    services.snapraid = {
      enable = true;

      inherit dataDisks parityFiles contentFiles;

      sync.interval = "*-*-* 00/6:00:00";
      scrub.interval = "daily";

      exclude = [
        "*.unrecoverable"
        "/tmp/"
        "/lost+found/"
        "/.Trash-*/"
      ];
    };
    # Maintenance must not treat an absent disk's underlying directory as
    # array storage. Also create the configured native content-file directory.
    systemd.services.snapraid-sync = maintenanceMounts;
    systemd.services.snapraid-scrub = maintenanceMounts;
  };
}
