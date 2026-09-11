# RomM

RomM catalogs ROMs and related artwork. Nixstead runs digest-pinned RomM and
MariaDB containers, creates the application directories, and mounts the ROM
library separately from application state.

## Enable and configure

```nix
nixstead.services.media.romm = {
  enable = true;
  domain = "romm.home.arpa";
  port = 8182;
  paths = {
    dataDir = "/var/lib/romm";
    libraryDir = "/mnt/media/roms";
  };
};
```

`images.application` and `images.database` can override the pinned images.
Application/database secrets and optional metadata-provider keys live in the
encrypted `romm` branch; generate them with
`nixstead --host <host> credentials bootstrap romm`.

## Initial credentials

The SOPS values are backend credentials, not a RomM web login. Open
`https://romm.home.arpa` and use RomM's first-run account creation. Nixstead
does not know the resulting password.

Inspect `docker-romm.service` and `docker-romm-db.service`.

## Backup and startup smoke

The shipped policy combines the configured application root, separate ROM
library path and a native MariaDB logical dump. Restore follows the configured
host account when it exists, or its numeric UID, and the shared media group.
Keep the encrypted credentials and their decryption keys separately. The
container's Redis volume is outside this application-data policy and is cleared
in the smoke fixture; queued work and cache continuity are not claimed.

The focused x86_64 fixture imports the exact production image digests, starts
the actual RomM and MariaDB containers with external catalogue providers
disabled, checks `/api/heartbeat`, and places a
small marker in each configured filesystem root. Its recovery check erases
those roots and the MariaDB volume before one clean encrypted Borg restore,
then checks application readiness and both markers. It exercises no ROM
acquisition, metadata provider, library/account workflow, repeated reboot or
upgrade. ARM configuration evaluation does not establish ARM runtime support.

The combined x86_64 startup/restore smoke passed in **683.94 seconds** with
RomM 5.2.0 and MariaDB 11.3.2. The isolated VM uses four cores to match RomM's
existing container CPU limit. Offline image loading and initial migrations
dominated the run; the shipped backup and restore commands completed in
31.79 and 32.94 seconds respectively. The native application retried once while
the fresh database initialized, then reached HTTP readiness before and after
recovery.
