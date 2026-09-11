# Storage, backup, and restore

Storage choices are machine-specific and therefore excluded from service
presets. Verify devices, filesystems, ownership, and recovery plans before
activation.

## CIFS client mounts

Declare the host-specific shares explicitly. CIFS only manages the mounts; it
does not assume share names or mount paths:

```nix
nixstead.services.cifs = {
  enable = true;
  shares = {
    media = {
      source = "//192.168.1.30/media";
      mountPoint = "/mnt/media";
    };
    appdata = {
      source = "//192.168.1.30/appdata";
      mountPoint = "/mnt/appdata";
      options = ["noperm" "dynperm"];
    };
    public = {
      source = "//192.168.1.30/public";
      mountPoint = "/mnt/public";
    };
  };
};
```

Customize or disable individual shares by editing the host's `shares` set:

```nix
nixstead.services.cifs.shares = {
  media = {
    source = "//192.168.1.30/Media";
    mountPoint = "/srv/media";
    options = [];
  };
  appdata = null;
  public = null;
};
```

Credentials come from the `cifs` secret domain and are written to a root-only
runtime file. Default mounts use systemd automount and `noauto` behavior.

## Local NAS stack

The NAS parent can default-enable mergerfs, SnapRAID, and Samba:

```nix
nixstead.services.nas = {
  enable = true;
  mergerfs.enable = true;
  snapraid.enable = true;
  samba.enable = true;
  # samba.shares must explicitly select existing paths and authenticated users.
  tankMount = "/mnt/tank";

  disks = {
    data = [
      {
        name = "data1";
        device = "/dev/disk/by-id/<data-disk-1>";
        mountPoint = "/mnt/data1";
        fsType = "ext4";
      }
      {
        name = "data2";
        device = "/dev/disk/by-id/<data-disk-2>";
        mountPoint = "/mnt/data2";
        fsType = "ext4";
      }
    ];

    parity = [
      {
        device = "/dev/disk/by-id/<parity-disk>";
        mountPoint = "/mnt/parity";
        fsType = "ext4";
      }
    ];
  };
};
```

The disk lists have no device defaults. Prefer stable `/dev/disk/by-id/` paths
that point to the selected disks. The setup wizard discovers whole disks,
shows their path, UUID, size, filesystem, and available space, then asks which
selected disks are parity disks and assigns the rest to mergerfs data. It never
partitions, formats, or otherwise modifies disks.

### mergerfs

Configured data mount points are combined at `tankMount`. The module creates
common Media, Public, Backup, Backups, and Appdata directories with the shared
media group.

### SnapRAID

Data-disk names and parity mount points generate SnapRAID configuration. Sync
runs every six hours and scrub runs daily. SnapRAID is not real-time RAID;
understand its snapshot/parity model before relying on it.

### Samba

The module exports no directories by default. Declare authenticated shares with
explicit paths and local users; writes require `readOnly = false`. See the
[Samba guide](services/samba.md) for credentials and network exposure.

## Service data paths

`nixstead.services.cifs.shares` is the single source of truth for CIFS mount points.
Share names are arbitrary, and service paths reference them directly:

```nix
nixstead.services.cifs = {
  enable = true;
  shares = {
    media = {
      source = "//storage.example/media";
      mountPoint = "/srv/media";
    };
    appdata = {
      source = "//storage.example/appdata";
      mountPoint = "/srv/appdata";
    };
    public = {
      source = "//storage.example/public";
      mountPoint = "/srv/public";
    };
  };
};

nixstead.services.media.romm.paths = {
  dataDir = "${config.nixstead.services.cifs.shares.appdata.mountPoint}/romm";
  libraryDir = "${config.nixstead.services.cifs.shares.public.mountPoint}/roms";
};

```

Without explicit path overrides, every service keeps its native or module-local
default. The setup wizard emits explicit overrides for enabled services whose
data role matches a selected CIFS share. The module derives `fileSystems` from
the share definitions and rejects relative or duplicate mount points. Native
units and OCI containers receive `RequiresMountsFor` dependencies for their
resolved service paths, so a failed remote mount prevents a service from
writing into the uncovered local directory. Misspelled service path keys and
relative paths fail module evaluation.

The runtime health check verifies selected CIFS mounts:

```bash
nixstead --host <host> --secrets-dir "$PWD/secrets" check runtime
```

## Service-data backups

Registry entries with backup metadata participate in the packaged scheduled
backup command and the manual `nixstead backup create` operation.
The backup workflow:

1. evaluates the selected host's resolved registry;
2. resolves typed paths rather than assuming `/var/lib/<name>`;
3. validates database policies and stops running application writers;
4. creates declared native/container PostgreSQL and MariaDB logical dumps, then
   stops companion databases when a physical snapshot is also declared;
5. stages application state and all registry-declared paths;
6. restarts services before Borg processing;
7. creates and verifies an encrypted Borg archive;
8. prunes to the configured retention policy (7 daily, 4 weekly, and 6 monthly by default);
9. compacts the repository; and
10. refreshes a `service-configs-latest` recovery copy.

For manual script runs, the default backup target is under the ignored
repository-local `Configs/` directory:

```text
Configs/
├── borg-service-data/
└── service-configs-latest/
```

Select the host explicitly for repository scripts. Set a passphrase or
passcommand and preserve it separately:

```bash
export BORG_PASSPHRASE='<strong-passphrase>'
sudo --preserve-env=BORG_PASSPHRASE \
  nixstead --host <host> backup create
```

Alternatively, supply the host for one invocation:

```bash
sudo --preserve-env=BORG_PASSPHRASE \
  nixstead --host <host> backup create
```

New repositories use `repokey-blake2` encryption. The script refuses an
existing unencrypted repository.

Use an off-machine target instead of the repository-local fallback:

```bash
export NIXSTEAD_BACKUP_REPOSITORY='ssh://backup@example.net/./borg/nixstead'
export BORG_PASSCOMMAND='cat /run/secrets/borg-passphrase'
sudo --preserve-env=NIXSTEAD_BACKUP_REPOSITORY,BORG_PASSCOMMAND \
  nixstead --host <host> backup create
```

Remote initialization requires the one-time explicit
`NIXSTEAD_BACKUP_INIT=true` opt-in. `NIXSTEAD_BACKUP_SCOPE=config` retains the
old exclusion-heavy snapshot; the default `full` scope is intended for recovery.
Secrets, the Nix store, the operating system, and large media roots that are not
declared in registry backup paths still require a separate policy.

Scheduled backups and restore rehearsals are opt-in:

```nix
nixstead.backups = {
  enable = true;
  repository = "ssh://backup@example.net/./borg/nixstead";
  environmentFile = "/run/secrets/nixstead-backup-env";
  schedule = "daily";
  verifySchedule = "weekly";
  # keepLast = 2; # replaces the default calendar retention with the newest two archives
};
```

Scheduled units run packaged executables from the Nix store and receive the
resolved service registry as immutable runtime metadata. They do not require a
checkout at `nixstead.host.repositoryPath`. Local Borg data and the latest scratch
recovery copy default to `/var/lib/nixstead-backups`; override
`nixstead.backups.stateDirectory` when a different persistent location is required.

Set `nixstead.backups.keepLast = 2` to retain only the two newest service
archives, including manual extra runs. This replaces all daily/weekly/monthly
retention rules. Repository scripts accept `NIXSTEAD_BACKUP_KEEP_LAST=2` for the
same behavior. With verification enabled, pruning happens after the new archive
passes verification.

Scheduled jobs require mounts for their state directory and local repository
before preparing any directories. They use a private local cache at
`/var/cache/nixstead-backups` for temporary staging and extraction, preserving
Unix metadata even when the archive repository is on CIFS. Temporary copies are
removed when the jobs exit; ensure local free space can hold the full selected
snapshot. The persistent latest recovery copy remains in the state directory.

Enable `nixstead.tools` to install the grouped command for guarded live restores.
It can also be run directly from the flake during clone-based recovery.

## Restore

Restore is refused without explicit `--apply`:

```bash
sudo nixstead --host <host> backup restore latest --apply

sudo nix run path:.#nixstead -- --host <host> backup restore latest --apply

sudo --preserve-env=BORG_PASSPHRASE \
  nixstead --host <host> backup restore \
  borg service-data-YYYY-MM-DD_HH-MM-SS --apply --restore-databases
```

The restore script evaluates registry mappings, stops each affected running
service before changing files, restores with `rsync --delete`, corrects
ownership, and restarts units that were previously running. Use
`--restart-services` to also start restored services that were not previously
active. Database-backed services require the explicit `--restore-databases` flag
because their logical imports replace matching database objects. Preflight
requires the exact nonempty `database-dumps/<service>.sql` for each selected
database policy before stopping services or changing files. A failed import
returns failure and leaves affected applications stopped for investigation.

RomM dumps the `romm` database from the running `romm-db` container before stopping
it. Restoring into a newly initialized `romm-db-data` volume imports the dump;
application directories alone cannot recover its database. Its transient Redis
cache is not covered. Immich dumps `immich` separately and snapshots its resolved
media directory; restoration requires the NixOS-created database role and pinned
PostgreSQL extensions. Machine-learning caches/models are reproducible and are
not photo recovery state. Preserve external libraries separately.

Native application dumps are database-scoped. The standalone PostgreSQL policy
retains a cluster-wide dump and physical state; use the same PostgreSQL major
version for physical restoration. Its logical dump includes cluster roles and
can affect every local database. Other consumers of a shared database must also
be quiesced before a cluster-wide restore. Old per-application `pg_dumpall` dumps
also have cluster-wide effects; inspect older SQL before applying it.

Paperless backups resolve the native data, document, and consumption directories;
Forgejo backups resolve native state and repository storage. Separate locations
are included as additional archive paths, while locations inside the primary
snapshot do not need duplicate copies. Wrapper path overrides and native defaults
therefore produce the same effective backup policy. Immich and Paperless logical
dump names follow their configured application database names.

After updating a host with separate Paperless or Forgejo storage, create a new
full backup before relying on recovery. Older archives that omitted those
locations cannot recover them, and the current restore preflight rejects missing
required archive paths. Keep the pinned configuration used to create older
archives when performing a deliberately partial recovery.

Old RomM/Immich archives lacking their own SQL file fail preflight. Do not treat
those archives as complete recovery points; create a new full backup after this
change. Preserve encrypted secrets, recipient identities, package/flake pins and
external media separately. `config` scope is not an application recovery backup.

`rsync --delete` means files absent from the selected backup are removed from
the target directory. Verify the archive and target host before applying.

List Borg archives first:

```bash
borg list Configs/borg-service-data
```

Run a non-destructive restore rehearsal that verifies archive data and performs
an actual extraction into scratch space:

```bash
NIXSTEAD_BACKUP_REPOSITORY='ssh://backup@example.net/./borg/nixstead' \
  nixstead --host <host> backup verify
```

The scratch command verifies Borg integrity, path coverage, required files and
SQL presence. It does **not** import SQL, boot an application, or prove recovery.
Only populated application tests listed in the [support matrix](support-matrix.md)
can supply that evidence. Other backup entries are candidate policies requiring
your own empty-state recovery trial before reliance.

## Recovery recommendations

- Test restoration on non-production data.
- Back up the Borg key/passphrase separately.
- Keep at least one copy outside the machine and outside the primary storage
  pool.
- Back up the admin age identity separately from the tracked encrypted host
  files; losing every recipient identity makes the ciphertext unrecoverable.
- Verify application-level database recovery requirements; a config snapshot is
  not always a transactionally complete application backup.
- Confirm free space before staging or restoring.

Samba no longer exports the tank or creates guest-access directories. See
[authenticated share configuration](services/samba.md) before enabling it.
