{
  config,
  lib,
  optionalRuntimePathOption,
  pkgs,
  secretPlaceholder,
  serviceBindAddress,
  serviceOptionFromRegistry,
  serviceRegistry,
  utils,
  ...
}: let
  cfg = config.nixstead.services.vaultwarden;
  native = config.services.vaultwarden;
  backupDir = native.backupDir;
  nativeDefaultDataFolder = "/var/lib/${
    if lib.versionOlder config.system.stateVersion "24.11"
    then "bitwarden_rs"
    else "vaultwarden"
  }";
  # The native module accepts both naming conventions and omits null values.
  setting = upper: camel: fallback:
    if (native.config.${camel} or null) != null
    then native.config.${camel}
    else if (native.config.${upper} or null) != null
    then native.config.${upper}
    else fallback;
  dataFolder = setting "DATA_FOLDER" "dataFolder" nativeDefaultDataFolder;
  belowDataFolder = path: builtins.isString path && lib.hasPrefix "${dataFolder}/" path && !(lib.elem ".." (lib.splitString "/" path));
  defaults = serviceRegistry.vaultwarden.defaults.backup;
  requiredMountUnits = map (mountPoint: "${utils.escapeSystemdPath mountPoint}.mount") (
    lib.attrNames (lib.filterAttrs (mountPoint: fs:
      fs.enable
      && mountPoint != "/"
      && backupDir != null
      && (backupDir == mountPoint || lib.hasPrefix "${mountPoint}/" backupDir))
    config.fileSystems)
  );
in {
  options.nixstead.services.vaultwarden = serviceOptionFromRegistry "vaultwarden" {
    pathOptions.backupDir = optionalRuntimePathOption "Optional absolute Vaultwarden backup directory; native backups remain disabled when unset.";
    extraOptions.backup = {
      user = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = defaults.user;
        description = "Existing account running the snapshot job and owning its destination. Use root for a private root-owned backup share.";
      };
      group = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = defaults.group;
        description = "Existing group owning the snapshot destination.";
      };
      schedule = lib.mkOption {
        type = lib.types.str;
        default = defaults.schedule;
        description = "Systemd calendar expression for Vaultwarden snapshots.";
      };
    };
  };

  config = lib.mkIf config.nixstead.services.vaultwarden.enable {
    sops.secrets."vaultwarden/adminToken" = {};

    sops.templates."vaultwarden.env" = {
      content = ''
        ADMIN_TOKEN=${secretPlaceholder "vaultwarden/adminToken"}
      '';
      restartUnits = ["vaultwarden.service"];
    };

    services.vaultwarden =
      {
        enable = true;
        environmentFile = [config.sops.templates."vaultwarden.env".path];
        config = {
          ROCKET_ADDRESS = serviceBindAddress "vaultwarden";
          ROCKET_PORT = config.nixstead.services.vaultwarden.port;
          DOMAIN = "https://${config.nixstead.services.vaultwarden.domain}";
          SIGNUPS_ALLOWED = false;
        };
      }
      // lib.optionalAttrs (config.nixstead.services.vaultwarden.paths.backupDir != null) {
        backupDir = config.nixstead.services.vaultwarden.paths.backupDir;
      };

    # Backup storage must not prevent the password server from starting.
    # Match the effective native default/aliases in a concrete systemd setting.
    # The native generated EnvironmentFile carries the same DATA_FOLDER value.
    systemd.services.vaultwarden.environment.DATA_FOLDER = dataFolder;
    assertions = lib.optionals (backupDir != null) [
      {
        assertion =
          native.dbBackend
          == "sqlite"
          && lib.elem (setting "DATABASE_URL" "databaseUrl" null) [null "sqlite://${dataFolder}/db.sqlite3" "${dataFolder}/db.sqlite3"]
          && lib.all belowDataFolder [
            (setting "ATTACHMENTS_FOLDER" "attachmentsFolder" "${dataFolder}/attachments")
            (setting "SENDS_FOLDER" "sendsFolder" "${dataFolder}/sends")
            (setting "RSA_KEY_FILENAME" "rsaKeyFilename" "${dataFolder}/rsa_key")
          ];
        message = "Vaultwarden native snapshots require local db.sqlite3 and attachment/send/key paths below DATA_FOLDER.";
      }
      {
        assertion = builtins.hasAttr cfg.backup.user config.users.users && builtins.hasAttr cfg.backup.group config.users.groups;
        message = "Vaultwarden backup.user and backup.group must name existing accounts.";
      }
    ];
    # Create the destination only after mounting it, with its chosen identity.
    systemd.tmpfiles.settings."10-vaultwarden" = lib.mkIf (backupDir != null) (lib.mkForce {});
    systemd.timers.backup-vaultwarden.timerConfig.OnCalendar = lib.mkIf (backupDir != null) cfg.backup.schedule;
    systemd.services.backup-vaultwarden = lib.mkIf (backupDir != null) {
      path = [pkgs.diffutils];
      unitConfig.RequiresMountsFor = [backupDir];
      requires = requiredMountUnits;
      after = requiredMountUnits;
      wantedBy = lib.mkForce [];
      before = lib.mkForce [];
      environment.TMPDIR = "/run/backup-vaultwarden";
      serviceConfig = {
        User = cfg.backup.user;
        Group = cfg.backup.group;
        ExecStartPre = ["+${pkgs.coreutils}/bin/install -d -m 0700 -o ${lib.escapeShellArg cfg.backup.user} -g ${lib.escapeShellArg cfg.backup.group} ${lib.escapeShellArg backupDir}"];
        # Upstream ignores sqlite3 failures and writes SQLite directly to CIFS.
        ExecStart = lib.mkForce "${pkgs.bash}/bin/bash ${./vaultwarden-backup.sh}";
        RuntimeDirectory = "backup-vaultwarden";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
      };
    };
  };
}
