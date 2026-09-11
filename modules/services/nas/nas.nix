{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.services.nas;
  allDisks = cfg.disks.data ++ cfg.disks.parity;
  diskMountAttrs = lib.listToAttrs (
    map (disk: {
      name = disk.mountPoint;
      value = {
        device = disk.device;
        fsType = disk.fsType;
        options = disk.options;
      };
    })
    allDisks
  );
in {
  options.nixstead.services.nas = {
    enable = lib.mkEnableOption "NAS stack";
    mergerfs.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Whether the mergerfs service is enabled.";
    };
    snapraid.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Whether the SnapRAID service is enabled.";
    };
    samba.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Whether the Samba service is enabled.";
    };
  };

  config = lib.mkMerge [
    {users.groups.${config.nixstead.host.groups.media}.gid = config.nixstead.host.groups.mediaGid;}
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.disks.data != [];
          message = "nixstead.services.nas.enable requires at least one configured data disk.";
        }
        {
          assertion = !cfg.mergerfs.enable || cfg.disks.data != [];
          message = "nixstead.services.nas.mergerfs requires at least one configured data disk.";
        }
        {
          assertion = !cfg.snapraid.enable || cfg.disks.parity != [];
          message = "nixstead.services.nas.snapraid requires at least one configured parity disk.";
        }
      ];
      fileSystems = diskMountAttrs;
    })
  ];

  imports = [
    ./disks.nix
    ./mergerfs.nix
    ./snapraid.nix
    ./samba.nix
  ];
}
