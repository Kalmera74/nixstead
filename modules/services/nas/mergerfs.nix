{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  cfg = config.nixstead.services.nas;
  dataMountPoints = map (disk: disk.mountPoint) cfg.disks.data;
  mergerfsDevice = lib.concatStringsSep ":" dataMountPoints;
  requiresMountsFor = "x-systemd.requires-mounts-for=${lib.concatStringsSep " " dataMountPoints}";
  requiredMountUnits = map (mountPoint: "${utils.escapeSystemdPath mountPoint}.mount") dataMountPoints;
in {
  config = lib.mkIf (cfg.mergerfs.enable && cfg.disks.data != []) {
    system.fsPackages = [pkgs.mergerfs];
    fileSystems."${cfg.tankMount}" = {
      device = mergerfsDevice;
      fsType = "fuse.mergerfs";
      options =
        [
          "defaults"
          "allow_other"
          "use_ino"
          "cache.files=auto-full"
          "category.create=mfs"
          "dropcacheonclose=true"
          "func.getattr=newest"
          "fsname=mergerfs"
          "moveonenospc=true"
          "nofail"
          requiresMountsFor
        ]
        ++ map (unit: "x-systemd.requires=${unit}") requiredMountUnits;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.tankMount} 0775 root ${config.nixstead.host.groups.media} -"
      "d ${cfg.tankMount}/Media 0775 root ${config.nixstead.host.groups.media} -"
      "d ${cfg.tankMount}/Public 0775 root ${config.nixstead.host.groups.media} -"
      "d ${cfg.tankMount}/Backup 0775 root ${config.nixstead.host.groups.media} -"
      "d ${cfg.tankMount}/Backups 0775 root ${config.nixstead.host.groups.media} -"
      "d ${cfg.tankMount}/Appdata 0775 root ${config.nixstead.host.groups.media} -"
    ];
  };
}
