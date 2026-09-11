{
  mkSystem,
  serviceContract,
  lib,
  ...
}: let
  configured =
    (mkSystem [
      {
        nixstead.services.vaultwarden = {
          enable = true;
          port = 28222;
          domain = "passwords.example.test";
          paths.backupDir = "/mnt/snapshots/vaultwarden";
          backup = {
            user = "root";
            group = "root";
            schedule = "weekly";
          };
        };
        fileSystems."/mnt/snapshots" = {
          device = "/dev/vdb";
          fsType = "ext4";
        };
      }
    ]).config;
  bare = (mkSystem [{nixstead.services.vaultwarden.enable = true;}]).config;
  invalid =
    (mkSystem [
      {
        nixstead.services.vaultwarden = {
          enable = true;
          paths.backupDir = "/srv/backup";
          backup.user = "absent";
        };
      }
    ]).config;
  job = configured.systemd.services.backup-vaultwarden;
in
  (serviceContract {
    id = "vaultwarden";
    port = 28222;
    nativeEnabled = c: c.services.vaultwarden.enable;
  })
  // {
    modernNativeRoot = bare.systemd.services.vaultwarden.environment.DATA_FOLDER == "/var/lib/vaultwarden" && bare.nixstead.serviceRegistry.vaultwarden.backup.paths == ["/var/lib/vaultwarden"];
    restoreUsesNativeUnitIdentity = let
      c =
        (mkSystem [
          {
            nixstead.services.vaultwarden.enable = true;
            users.users.vault-fixture = {
              isSystemUser = true;
              group = "vault-group";
            };
            users.groups.vault-group = {};
            systemd.services.vaultwarden.serviceConfig = {
              User = lib.mkForce "vault-fixture";
              Group = lib.mkForce "vault-group";
            };
          }
        ]).config;
    in
      c.nixstead.serviceRegistry.vaultwarden.backup.owner == "vault-fixture" && c.nixstead.serviceRegistry.vaultwarden.backup.group == "vault-group";
    legacyNativeRoot = let
      c =
        (mkSystem [
          {
            system.stateVersion = lib.mkForce "23.11";
            nixstead.services.vaultwarden.enable = true;
          }
        ]).config;
    in
      c.systemd.services.vaultwarden.environment.DATA_FOLDER == "/var/lib/bitwarden_rs" && c.systemd.services.vaultwarden.serviceConfig.StateDirectory == "bitwarden_rs" && c.nixstead.serviceRegistry.vaultwarden.backup.paths == ["/var/lib/bitwarden_rs"];
    canonicalNativePathOverride =
      (mkSystem [
        {
          nixstead.services.vaultwarden.enable = true;
          services.vaultwarden.config.DATA_FOLDER = "/srv/owned-vault";
        }
      ]).config.nixstead.serviceRegistry.vaultwarden.backup.paths
      == ["/srv/owned-vault"];
    aliasNativePathOverride =
      (mkSystem [
        {
          nixstead.services.vaultwarden.enable = true;
          services.vaultwarden.config.dataFolder = "/srv/owned-vault";
        }
      ]).config.nixstead.serviceRegistry.vaultwarden.backup.paths
      == ["/srv/owned-vault"];
    effectiveRootMatchesNativeSnapshot = lib.all (settings: let
      c =
        (mkSystem [
          {
            system.stateVersion = lib.mkForce "23.11";
            nixstead.services.vaultwarden = {
              enable = true;
              paths.backupDir = "/srv/snapshots";
            };
            services.vaultwarden.config = settings;
          }
        ]).config;
    in
      c.nixstead.serviceRegistry.vaultwarden.backup.paths == [c.systemd.services.backup-vaultwarden.environment.DATA_FOLDER]) [
      {DATA_FOLDER = null;}
      {dataFolder = "/srv/owned-vault";}
      {
        DATA_FOLDER = "/srv/first-vault";
        dataFolder = "/srv/native-last-vault";
      }
    ];
    defaultSQLiteAndKeyRequired = bare.nixstead.serviceRegistry.vaultwarden.backup.requiredFiles == ["db.sqlite3" "rsa_key.pem"];
    externalDatabaseNotMisidentifiedAsSQLite = let
      c =
        (mkSystem [
          {
            nixstead.services.vaultwarden.enable = true;
            services.vaultwarden.dbBackend = "postgresql";
            services.vaultwarden.config.databaseUrl = "postgresql:///vaultwarden";
          }
        ]).config;
    in
      c.nixstead.serviceRegistry.vaultwarden.backup.requiredFiles == ["rsa_key.pem"] && lib.all (a: a.assertion) c.assertions;
    customKeyNotMisidentified =
      (mkSystem [
        {
          nixstead.services.vaultwarden.enable = true;
          services.vaultwarden.config.rsaKeyFilename = "/var/lib/vaultwarden/signing-key";
        }
      ]).config.nixstead.serviceRegistry.vaultwarden.backup.requiredFiles
      == ["db.sqlite3"];
    invalidNativeSnapshotRejected = lib.all (native:
      lib.any (a: !a.assertion && lib.hasInfix "native snapshots require" a.message)
      (mkSystem [
        {
          nixstead.services.vaultwarden = {
            enable = true;
            paths.backupDir = "/srv/snapshots";
          };
          services.vaultwarden = native;
        }
      ]).config.assertions) [{dbBackend = "postgresql";} {config.databaseUrl = "sqlite:///var/lib/vaultwarden/other.db";} {config.attachmentsFolder = "/srv/assets";} {config.rsaKeyFilename = "/var/lib/vaultwarden/../unowned-key";}];
    nativeAccessPolicy = configured.services.vaultwarden.config.ROCKET_ADDRESS == "127.0.0.1" && configured.services.vaultwarden.config.ROCKET_PORT == 28222 && configured.services.vaultwarden.config.DOMAIN == "https://passwords.example.test" && !configured.services.vaultwarden.config.SIGNUPS_ALLOWED;
    adminTokenIsRuntimeTemplate = configured.services.vaultwarden.environmentFile == [configured.sops.templates."vaultwarden.env".path] && lib.hasInfix configured.sops.placeholder."vaultwarden/adminToken" configured.sops.templates."vaultwarden.env".content && !(configured.services.vaultwarden.config ? ADMIN_TOKEN);
    noImplicitNativeSnapshot = bare.services.vaultwarden.backupDir == null;
    snapshotPathIdentitySchedule = configured.services.vaultwarden.backupDir == "/mnt/snapshots/vaultwarden" && job.serviceConfig.User == "root" && job.serviceConfig.Group == "root" && configured.systemd.timers.backup-vaultwarden.timerConfig.OnCalendar == "weekly";
    snapshotWaitsForMount = lib.elem "/mnt/snapshots/vaultwarden" job.unitConfig.RequiresMountsFor && lib.elem "mnt-snapshots.mount" job.requires;
    serverIndependentOfSnapshotMount = !(lib.elem "/mnt/snapshots/vaultwarden" (configured.systemd.services.vaultwarden.unitConfig.RequiresMountsFor or []));
    privateTemporarySnapshot = job.serviceConfig.RuntimeDirectoryMode == "0700" && job.environment.TMPDIR == "/run/backup-vaultwarden";
    snapshotHasByteComparisonTool = lib.any (package: lib.getName package == "diffutils") job.path;
    archiveApplicationState = configured.nixstead.serviceRegistry.vaultwarden.backup.paths == ["/var/lib/vaultwarden"];
    invalidSnapshotIdentityRejected = lib.any (a: !a.assertion && lib.hasInfix "must name existing accounts" a.message) invalid.assertions;
  }
