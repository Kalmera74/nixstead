{
  config,
  lib,
  ...
}: let
  cfg = config.nixstead.services.nas.samba;
in {
  options.nixstead.services.nas.samba.shares = lib.mkOption {
    default = {};
    description = "Explicit authenticated SMB shares. No directory is exported by default; provision Samba passwords separately with smbpasswd.";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        path = lib.mkOption {
          type = lib.types.strMatching "^/.*";
          description = "Existing directory to share; Nixstead does not create or change ownership of it.";
        };
        users = lib.mkOption {
          type = lib.types.listOf lib.types.nonEmptyStr;
          default = [];
          description = "Existing local users allowed to authenticate to this share.";
        };
        readOnly = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether authenticated clients have read-only access.";
        };
      };
    });
  };

  config = lib.mkIf cfg.enable {
    assertions =
      lib.mapAttrsToList (name: share: {
        assertion = name != "global" && share.users != [] && lib.all (user: builtins.hasAttr user config.users.users && builtins.match "[a-zA-Z_][a-zA-Z0-9_-]*" user != null) share.users;
        message = "Samba share ${name} must have a non-reserved name and an explicit list of existing local users.";
      })
      cfg.shares;

    services.samba = {
      enable = true;
      openFirewall = false;
      settings =
        {
          global = {
            "workgroup" = "WORKGROUP";
            "server string" = "nixos-nas";
            "security" = "user";
            "map to guest" = "Never";
            "restrict anonymous" = 2;
          };
        }
        // lib.mapAttrs (_: share: {
          path = share.path;
          "browseable" = "yes";
          "read only" =
            if share.readOnly
            then "yes"
            else "no";
          "guest ok" = "no";
          "valid users" = lib.concatStringsSep " " share.users;
          "create mask" = "0660";
          "directory mask" = "0770";
        })
        cfg.shares;
    };
  };
}
