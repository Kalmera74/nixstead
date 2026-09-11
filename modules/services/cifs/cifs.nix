{
  config,
  lib,
  pkgs,
  secretPlaceholder,
  ...
}: let
  inherit (lib) mkIf mkOption types;

  cfg = config.nixstead.services.cifs;

  shareType = types.submodule {
    options = {
      source = mkOption {
        type = types.str;
      };

      mountPoint = mkOption {
        type = types.path;
      };

      options = mkOption {
        type = types.listOf types.str;
        default = [];
      };
    };
  };

  mountFor = _: share:
    lib.nameValuePair share.mountPoint {
      device = share.source;
      fsType = "cifs";
      options = cfg.mountOptions ++ share.options;
    };
  enabledShares = lib.filterAttrs (_: share: share != null) cfg.shares;
  mountPoints = map (share: share.mountPoint) (lib.attrValues enabledShares);
in {
  options.nixstead.services.cifs = mkOption {
    type = types.submodule {
      options = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };

        credentialsFile = mkOption {
          type = types.str;
          default = "/run/secrets/cifs-credentials";
        };

        uid = mkOption {
          type = types.ints.unsigned;
          default = config.nixstead.host.user.uid;
        };

        gid = mkOption {
          type = types.str;
          default = config.nixstead.host.groups.media;
        };

        mountOptions = mkOption {
          type = types.listOf types.str;
          default = [
            "credentials=${cfg.credentialsFile}"
            "uid=${toString cfg.uid}"
            "gid=${cfg.gid}"
            "file_mode=0775"
            "dir_mode=0775"
            "vers=3.0"
            # Keep hardlinked download and library paths from sharing a stale
            # client inode while the download client still has one path open.
            "noserverino"
            "x-systemd.automount"
            "noauto"
          ];
        };

        shares = mkOption {
          type = types.attrsOf (types.nullOr shareType);
          default = {};
          description = "Explicit SMB/CIFS shares to mount; source and mountPoint are host-specific typed values.";
        };
      };
    };
    default = {};
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.any (share: share != null) (lib.attrValues cfg.shares);
        message = "nixstead.services.cifs requires at least one share when enabled.";
      }
      {
        assertion = lib.length mountPoints == lib.length (lib.unique mountPoints);
        message = "Enabled CIFS shares must use unique mountPoint values.";
      }
    ];

    fileSystems = lib.mapAttrs' mountFor enabledShares;

    environment.systemPackages = [pkgs.cifs-utils];

    sops.secrets = {
      "cifs/username" = {};
      "cifs/password" = {};
      "cifs/domain" = {};
    };

    sops.templates."cifs-credentials" = {
      path = cfg.credentialsFile;
      content = ''
        username=${secretPlaceholder "cifs/username"}
        password=${secretPlaceholder "cifs/password"}
        domain=${secretPlaceholder "cifs/domain"}
      '';
      mode = "0400";
    };
  };
}
