{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  cfg = config.nixstead.backups;
  runtimePath = [
    pkgs.borgbackup
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.jq
    pkgs.postgresql
    pkgs.rsync
    pkgs.systemd
    pkgs.util-linux
  ];
  tools = import ../../scripts/package.nix {
    inherit pkgs;
    repositoryRoot = config.nixstead.host.repositoryPath;
    configurationName = config.nixstead.host.configurationName;
  };
  registryFile = pkgs.writeText "nixstead-service-registry.json" (builtins.toJSON config.nixstead.serviceRegistry);
  backupProgram = tools.commands.backup-service-configs;
  restoreTestProgram = tools.commands.test-service-backup-restore;
  restoreProgram = tools.commands.restore-service-configs;
  commonEnvironment = {
    NIXSTEAD_BACKUP_REPOSITORY =
      if cfg.repository == null
      then ""
      else cfg.repository;
    NIXSTEAD_BACKUP_SCOPE = cfg.scope;
    NIXSTEAD_HOST = config.nixstead.host.configurationName;
    NIXSTEAD_SECRETS_DIR = builtins.dirOf (toString config.nixstead.secrets.sopsFile);
    NIXSTEAD_BACKUP_STATE_DIR = cfg.stateDirectory;
    NIXSTEAD_REGISTRY_FILE = registryFile;
  };
  environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
  backupMounts =
    [cfg.stateDirectory]
    ++ lib.optional (cfg.repository != null && lib.hasPrefix "/" cfg.repository) cfg.repository;
  requiredMountUnits = map (mountPoint: "${utils.escapeSystemdPath mountPoint}.mount") (
    lib.attrNames (lib.filterAttrs (
        mountPoint: fs:
          fs.enable
          && mountPoint != "/"
          && lib.any (path: path == mountPoint || lib.hasPrefix "${mountPoint}/" path) backupMounts
      )
      config.fileSystems)
  );
  prepareDirectories = ''
    install -d -m 0700 ${lib.escapeShellArg cfg.stateDirectory}
  '';
in {
  options.nixstead.backups = {
    enable = lib.mkEnableOption "scheduled registry-driven service backups";
    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "ssh://backup@example.net/./borg/nixstead";
      description = "Local or remote Borg repository. Scheduled backups require an explicit target.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "^/.*");
      default = null;
      example = "/run/secrets/nixstead-backup-env";
      description = "Optional runtime EnvironmentFile containing BORG_PASSPHRASE or BORG_PASSCOMMAND.";
    };
    scope = lib.mkOption {
      type = lib.types.enum ["full" "config"];
      default = "full";
      description = "Backup scope; full includes application data, while config retains legacy exclusions.";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd calendar expression for backups.";
    };
    verifySchedule = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "systemd calendar expression for archive extraction and required-file checks; does not test application recovery.";
    };
    keepLast = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      example = 2;
      description = "Keep only this many newest service archives. When unset, retain 7 daily, 4 weekly and 6 monthly archives.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "^/.*";
      default = "/var/lib/nixstead-backups";
      description = "Persistent backup state and the latest recovery copy. Temporary staging uses a private local cache.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.repository != null;
        message = "nixstead.backups.repository must be set when scheduled backups are enabled.";
      }
      {
        assertion = cfg.environmentFile == null || !lib.hasPrefix "/nix/store/" cfg.environmentFile;
        message = "nixstead.backups.environmentFile must remain outside the world-readable Nix store.";
      }
    ];

    systemd.services.nixstead-service-backup = {
      description = "Back up registry-managed service data";
      path = runtimePath;
      unitConfig.RequiresMountsFor = backupMounts;
      # Keep an explicit dependency even when systemd masks a configured mount.
      requires = requiredMountUnits;
      after = requiredMountUnits;
      preStart = prepareDirectories;
      environment =
        commonEnvironment
        // {
          NIXSTEAD_BACKUP_KEEP_LAST =
            if cfg.keepLast == null
            then ""
            else toString cfg.keepLast;
          # Preserve Unix metadata before archiving, including with a CIFS target.
          TMPDIR = "/var/cache/nixstead-backups";
        };
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = environmentFiles;
        ExecStart = "${backupProgram}/bin/nixstead-backup-service-configs";
        UMask = "0077";
        CacheDirectory = "nixstead-backups";
        CacheDirectoryMode = "0700";
      };
    };

    systemd.services.nixstead-backup-restore-test = {
      description = "Verify extraction and required files in the latest service backup";
      path = runtimePath;
      unitConfig.RequiresMountsFor = backupMounts;
      requires = requiredMountUnits;
      after = requiredMountUnits;
      preStart = prepareDirectories;
      environment = commonEnvironment // {TMPDIR = "/var/cache/nixstead-backups";};
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = environmentFiles;
        ExecStart = "${restoreTestProgram}/bin/nixstead-test-service-backup-restore";
        UMask = "0077";
        CacheDirectory = "nixstead-backups";
        CacheDirectoryMode = "0700";
      };
    };

    systemd.timers.nixstead-service-backup = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    systemd.timers.nixstead-backup-restore-test = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.verifySchedule;
        Persistent = true;
        RandomizedDelaySec = "2h";
      };
    };
  };
}
