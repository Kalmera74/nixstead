{
  lib,
  mkSystem,
  hasFailedAssertion,
  publicModules,
}: let
  starter = (mkSystem [publicModules.default {nixstead.preset = "media-starter";}]).config;
  nas = (mkSystem [publicModules.nas {nixstead.services.nas.samba.enable = true;}]).config;
  custom =
    (mkSystem [
      publicModules.default
      {
        nixstead.services.productivity.nextcloud = {
          enable = true;
          paths.dataDir = "/srv/cloud-data";
        };
        services.nextcloud.home = "/srv/cloud-home";
        nixstead.services.media.immich = {
          enable = true;
          paths.mediaLocation = "/srv/photos";
        };
        services.immich.user = "photoowner";
        users.users.photoowner = {
          isSystemUser = true;
          group = "users";
        };
      }
    ]).config;
  registry = import ../modules/services/registry.nix;
  privateBackups =
    (mkSystem [
      publicModules.default
      ./fixtures/private-backups.nix
      {
        nixstead.services.cifs.enable = true;
        nixstead.services.vaultwarden = {
          enable = true;
          paths.backupDir = "/mnt/private-backups/test-node/vaultwarden";
        };
      }
    ]).config;
  independentMedia =
    (mkSystem [
      publicModules.media
      {
        nixstead.services.media.immich.enable = true;
        nixstead.services.media.tdarr.enable = true;
      }
    ]).config;
  separateState =
    (mkSystem [
      publicModules.default
      {
        nixstead.services.productivity.paperless = {
          enable = true;
          paths.mediaDir = "/srv/documents";
          paths.consumeDir = "/srv/incoming";
        };
        services.paperless.dataDir = "/srv/paperless";
        nixstead.services.dev.forgejo = {
          enable = true;
          paths.repositoryDir = "/srv/repositories";
        };
        services.forgejo.stateDir = "/srv/forgejo";
      }
    ]).config;
in {
  independentMediaAccountsExist =
    !independentMedia.nixstead.host.user.enable
    && independentMedia.services.immich.user == "immich"
    && independentMedia.services.tdarr.user == "tdarr"
    && independentMedia.users.users.immich.isSystemUser
    && independentMedia.users.users.tdarr.isSystemUser;
  immichCreatesOnlyItsApplicationDatabase =
    independentMedia.services.postgresql.ensureDatabases
    == ["immich"]
    && custom.services.postgresql.ensureDatabases == ["immich"]
    && (lib.head custom.services.postgresql.ensureUsers).name == "photoowner";
  customMediaIdentityRequiresExistingAccount = hasFailedAssertion [
    publicModules.media
    {
      nixstead.services.media.immich.enable = true;
      services.immich.user = "missing-photo-owner";
    }
  ] "configured Immich user must exist";
  paperlessCoversSeparateNativeState =
    separateState.nixstead.serviceRegistry.paperless.backup.paths == ["/srv/paperless" "/srv/documents" "/srv/incoming"];
  forgejoCoversSeparateRepositoryState =
    separateState.nixstead.serviceRegistry.forgejo.backup.paths == ["/srv/forgejo" "/srv/repositories"];
  defaultPaperlessSnapshotDoesNotDuplicateNestedPaths =
    (mkSystem [publicModules.productivity {nixstead.services.productivity.paperless.enable = true;}]).config.nixstead.serviceRegistry.paperless.backup.paths == ["/var/lib/paperless"];
  paperlessUsesOnlyNativeSecretGenerator =
    separateState.systemd.services.paperless-web.preStart
    == ""
    && separateState.systemd.services.paperless-web.serviceConfig.EnvironmentFile == ["/srv/paperless/nixos-paperless-secret-key.env"]
    && builtins.hasAttr "paperless-secret-key" separateState.systemd.services;
  forgejoDoesNotImposeMigrationTimeouts =
    !((separateState.services.forgejo.settings."git.timeout" or {}) ? MIGRATE)
    && !(registry.forgejo.proxy ? extraLocationConfig)
    && !(registry.forgejo.proxy ? extraVhostConfig);
  privateVaultwardenBackupIsReusable = let
    evaluated =
      (mkSystem [
        publicModules.vaultwarden
        {
          fileSystems."/srv/private-backups" = {
            device = "/dev/backup";
            fsType = "ext4";
          };
          nixstead.services.vaultwarden = {
            enable = true;
            paths.backupDir = "/srv/private-backups/vault";
            backup = {
              user = "root";
              group = "root";
              schedule = "weekly";
            };
          };
        }
      ]).config;
    job = evaluated.systemd.services.backup-vaultwarden;
  in
    job.serviceConfig.User
    == "root"
    && job.serviceConfig.Group == "root"
    && job.wantedBy == []
    && job.before == []
    && lib.elem "srv-private\\x2dbackups.mount" job.requires
    && evaluated.systemd.timers.backup-vaultwarden.timerConfig.OnCalendar == "weekly"
    && evaluated.systemd.tmpfiles.settings."10-vaultwarden" == {};
  privateBackupMountRequiresOnlyAvailableServices = let
    prefix = "x-systemd.requires=";
    dependencies = map (lib.removePrefix prefix) (
      lib.filter (lib.hasPrefix prefix) privateBackups.fileSystems."/mnt/private-backups".options
    );
  in
    !privateBackups.sops.useSystemdActivation
    && privateBackups.sops.templates."cifs-credentials".path == privateBackups.nixstead.services.cifs.credentialsFile
    && lib.all (unit: builtins.hasAttr unit privateBackups.systemd.units) dependencies;
  privateBackupMountIsRequiredByBackupJobs = lib.all (
    name: lib.elem "mnt-private\\x2dbackups.mount" privateBackups.systemd.services.${name}.requires
  ) ["backup-vaultwarden" "nixstead-service-backup" "nixstead-backup-restore-test"];
  vaultwardenStartsWithoutBackupStorage =
    !(lib.elem "/mnt/private-backups/test-node/vaultwarden"
      (privateBackups.systemd.services.vaultwarden.unitConfig.RequiresMountsFor or []));
  lokiKeepsInternalGrpcOnLoopback = lib.all (
    exposure: let
      evaluated =
        (mkSystem [
          publicModules.dev
          {
            nixstead.services.dev.loki.enable = true;
            nixstead.host.network.exposure.services.loki = exposure;
          }
        ]).config;
      loki = evaluated.services.loki.configuration;
    in
      loki.server.grpc_listen_address
      == "127.0.0.1"
      && loki.common.instance_addr == "127.0.0.1"
      && loki.frontend.address == "127.0.0.1"
      && loki.server.http_listen_address
      == (
        if exposure == "loopback"
        then "127.0.0.1"
        else "0.0.0.0"
      )
  ) ["loopback" "lan"];
  vaultwardenBackupRequiresItsMount = let
    evaluated =
      (mkSystem [
        publicModules.vaultwarden
        {
          nixstead.services.vaultwarden.enable = true;
          nixstead.services.vaultwarden.paths.backupDir = "/mnt/backup/vaultwarden";
        }
      ]).config;
    backup = evaluated.systemd.services.backup-vaultwarden;
  in
    lib.elem "/mnt/backup/vaultwarden" backup.unitConfig.RequiresMountsFor
    && backup.environment.TMPDIR == "/run/backup-vaultwarden"
    && backup.serviceConfig.RuntimeDirectory == "backup-vaultwarden";
  immichMlHasPrivateRuntimeDirectory = let
    unit = custom.systemd.services.immich-machine-learning;
  in
    unit.serviceConfig.ProtectHome
    && unit.serviceConfig.RuntimeDirectory == "immich-machine-learning"
    && unit.serviceConfig.RuntimeDirectoryMode == "0700"
    && unit.environment.XDG_RUNTIME_DIR == "/run/immich-machine-learning";
  starterIsSmall =
    lib.attrNames (lib.filterAttrs (_: entry: entry.enabled) starter.nixstead.serviceRegistry)
    == ["homepage" "jellyfin" "nginx" "prowlarr" "qbittorrent" "radarr" "seerr" "sonarr"];
  starterDoesNotEnableParents = !starter.nixstead.services.arr.enable && !starter.nixstead.services.media.enable;
  starterChildCanBeDisabled =
    !(mkSystem [
      publicModules.default
      {
        nixstead.preset = "media-starter";
        nixstead.services.media.seerr.enable = false;
      }
    ]).config.nixstead.serviceRegistry.seerr.enabled;
  noImplicitSambaShares = lib.attrNames nas.services.samba.settings == ["global"];
  noSambaGuests = nas.services.samba.settings.global."map to guest" == "Never";
  sambaRequiresUsers = hasFailedAssertion [
    publicModules.nas
    {
      nixstead.services.nas.samba = {
        enable = true;
        shares.data.path = "/srv/data";
      };
    }
  ] "explicit list of existing local users";
  sambaDefaultsReadOnly = let
    configured =
      (mkSystem [
        publicModules.nas
        {
          users.users.reader.isNormalUser = true;
          nixstead.services.nas.samba = {
            enable = true;
            shares.data = {
              path = "/srv/data";
              users = ["reader"];
            };
          };
        }
      ]).config.services.samba.settings.data;
  in
    configured."read only" == "yes" && configured."guest ok" == "no" && configured."valid users" == "reader";
  nextcloudCoversHomeAndData = custom.nixstead.serviceRegistry.nextcloud.backup.paths == ["/srv/cloud-home" "/srv/cloud-data"];
  immichCoversDatabaseAndMedia = let
    b = custom.nixstead.serviceRegistry.immich.backup;
  in
    b.paths
    == ["/srv/photos"]
    && b.database == "postgresql"
    && b.databaseName == custom.services.immich.database.name
    && b.owner == custom.services.immich.user
    && b.group == custom.services.immich.group;
  rommDeclaresNamedVolumeDatabase =
    registry.romm.backup.databaseContainer
    == "romm-db"
    && registry.romm.backup.databaseName == "romm"
    && registry.romm.backup.databaseUnit == "docker-romm-db.service";
  databasePoliciesAreExecutable = lib.all (entry: let
    b = entry.backup;
  in
    b
    == null
    || b.database == null
    || (lib.elem b.database ["postgresql" "postgresql-container" "mariadb-container" "elasticsearch-container"]
      && b ? databaseUnit
      && (b.database == "postgresql" || (b ? databaseContainer && b ? databaseName)))) (lib.attrValues registry);
}
