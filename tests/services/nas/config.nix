{
  mkSystem,
  lib,
  ...
}: let
  base.nixstead.services.nas = {
    enable = true;
    tankMount = "/srv/pool";
    disks = {
      data = [
        {
          name = "data1";
          device = "/dev/vdb";
          mountPoint = "/mnt/data1";
          fsType = "ext4";
        }
      ];
      parity = [
        {
          device = "/dev/vdc";
          mountPoint = "/mnt/parity";
          fsType = "ext4";
        }
      ];
    };
  };
  c = (mkSystem [base]).config;
  disabled = (mkSystem [base {nixstead.services.nas.enable = lib.mkForce false;}]).config;
  childDisabled =
    (mkSystem [
      base
      {
        nixstead.services.nas = {
          mergerfs.enable = false;
          snapraid.enable = false;
          samba.enable = false;
        };
      }
    ]).config;
  noData = (mkSystem [{nixstead.services.nas.enable = true;}]).config;
  noParity = (mkSystem [base {nixstead.services.nas.disks.parity = lib.mkForce [];}]).config;
in {
  selectedChildren = c.services.snapraid.enable && c.services.samba.enable && c.fileSystems."/srv/pool".fsType == "fuse.mergerfs";
  explicitDiskMounts = c.fileSystems."/mnt/data1".device == "/dev/vdb" && c.fileSystems."/mnt/parity".device == "/dev/vdc";
  disabledRemovesDisksAndChildren = !(disabled.fileSystems ? "/mnt/data1") && !(disabled.fileSystems ? "/srv/pool") && !disabled.services.snapraid.enable && !disabled.services.samba.enable;
  parentAllowsChildDisable = !childDisabled.services.snapraid.enable && !childDisabled.services.samba.enable && !(childDisabled.fileSystems ? "/srv/pool") && childDisabled.fileSystems ? "/mnt/data1";
  mergerfsWaitsForDataMount = c.fileSystems."/srv/pool".device == "/mnt/data1" && lib.elem "x-systemd.requires-mounts-for=/mnt/data1" c.fileSystems."/srv/pool".options;
  mergerfsRequiresEveryDataMount = lib.all (unit: lib.elem "x-systemd.requires=${unit}" c.fileSystems."/srv/pool".options) ["mnt-data1.mount"];
  nativeMountHelperInstalled = lib.any (package: package.pname or "" == "mergerfs") c.system.fsPackages;
  parityAndContentWiring = c.services.snapraid.dataDisks.data1 == "/mnt/data1/" && c.services.snapraid.parityFiles == ["/mnt/parity/snapraid.parity"] && lib.all (p: lib.elem p c.services.snapraid.contentFiles) ["/var/lib/snapraid/snapraid.content" "/mnt/data1/snapraid.content" "/mnt/parity/snapraid.content"];
  sharedPoolGroupExists = c.users.groups.${c.nixstead.host.groups.media}.gid == c.nixstead.host.groups.mediaGid;
  maintenanceWaitsForEveryDisk = lib.all (unit:
    c.systemd.services.${unit}.unitConfig.RequiresMountsFor
    == ["/mnt/data1" "/mnt/parity"]
    && c.systemd.services.${unit}.unitConfig.ConditionPathIsMountPoint == ["/mnt/data1" "/mnt/parity"]
    && c.systemd.services.${unit}.serviceConfig.StateDirectory == "snapraid") ["snapraid-sync" "snapraid-scrub"];
  noImplicitShares = builtins.attrNames c.services.samba.settings == ["global"];
  missingDataRejected = lib.any (a: !a.assertion && lib.hasInfix "at least one configured data disk" a.message) noData.assertions;
  missingParityRejected = lib.any (a: !a.assertion && lib.hasInfix "at least one configured parity disk" a.message) noParity.assertions;
  validSystem = builtins.isString c.system.build.toplevel.drvPath;
}
