# SnapOtter

SnapOtter provides web-based image, video, audio, PDF, and file manipulation.
Nixstead runs hardened, digest-pinned application, PostgreSQL, and Redis
containers with persistent state and workspace directories.

## Enable and configure

```nix
nixstead.services.productivity.snapotter = {
  enable = true;
  domain = "images.home.arpa";
  port = 8187;
  paths.dataDir = "/var/lib/snapotter";
  auth.enable = true;
};
```

Generate the default login and backend secrets with
`nixstead --host <host> credentials bootstrap snapotter`. Set `auth.enable = false`
only on a trusted network; it removes application authentication.

## Initial credentials

The initial username is `admin`. Read its password with:

```bash
sudo cat /run/secrets/snapotter/defaultPassword
```

The application requires changing it on first login. Inspect
`docker-snapotter.service` and its database and Redis units.

## Backup and smoke scope

The registry owns the entire configured `paths.dataDir`, including application files, workspace, PostgreSQL data and Redis persistence.
The shipped backup coordinates the three containers and includes a logical
PostgreSQL dump. Restore uses the same pinned profile and the original runtime
SOPS credentials. Keep the encrypted source and its recipient identity
separately; they are not part of this application archive.

The dedicated suite is configuration-only: all 32 assertions passed on
x86_64-linux and aarch64-linux. Native startup and clean backup/restore are
unverified. The exact supported amd64 image contains approximately 3.56 GiB of
compressed layers, so it is excluded from the maintained fast smoke baseline.
No business-workflow, failure, lifecycle or upgrade behavior is claimed.

Directory setup uses the configured numeric host UID and media GID, matching
the container's `PUID`/`PGID`. Importing the service alone does not require a
personal host account with that name.
