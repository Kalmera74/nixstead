{lib, ...}: {
  options.nixstead.services.nas = {
    tankMount = lib.mkOption {
      type = lib.types.path;
      default = "/srv/nas";
      description = "Merged mergerfs root mount point.";
    };

    disks = {
      data = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Disk ID used by SnapRAID.";
              };
              device = lib.mkOption {
                type = lib.types.str;
                description = "Block device path.";
              };
              mountPoint = lib.mkOption {
                type = lib.types.path;
                description = "Mount point for this data disk.";
              };
              fsType = lib.mkOption {
                type = lib.types.str;
                description = "Filesystem type for this data disk.";
              };
              options = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["nofail"];
                description = "Mount options for this disk.";
              };
            };
          }
        );
        default = [];
        description = ''
          NAS data disks.
        '';
      };

      parity = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              device = lib.mkOption {
                type = lib.types.str;
                description = "Block device path.";
              };
              mountPoint = lib.mkOption {
                type = lib.types.path;
                description = "Mount point for this parity disk.";
              };
              fsType = lib.mkOption {
                type = lib.types.str;
                description = "Filesystem type for this parity disk.";
              };
              options = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["nofail"];
                description = "Mount options for this disk.";
              };
            };
          }
        );
        default = [];
        description = ''
          NAS parity disks.
        '';
      };
    };
  };
}
