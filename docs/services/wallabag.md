# Wallabag

Wallabag saves and organizes articles for later reading. Nixstead runs
digest-pinned Wallabag, MariaDB, and Redis containers with persistent database
and image directories.

## Enable and configure

```nix
nixstead.services.productivity.wallabag = {
  enable = true;
  domain = "wallabag.home.arpa";
  port = 8185;
  paths.dataDir = "/var/lib/wallabag";
};
```

Generate the database credential with
`nixstead --host <host> credentials bootstrap wallabag`. Public registration is
disabled by the container configuration.

The service backup stops the writers, creates a logical MariaDB dump, and
archives the application database and image directory. Redis is a disposable
cache and is rebuilt when the stack starts.

The combined x86 VM check intentionally stays small: it starts the three exact
pinned images, waits for the configured HTTP endpoint, and runs one encrypted
backup and clean restore. It does not exercise Wallabag account or article
workflows.

## Initial credentials

The encrypted database password is not a web login. The pinned upstream image
creates the initial UI login `wallabag` with password `wallabag`; change it
immediately after opening `https://wallabag.home.arpa`. Nixstead does not store
the replacement. See the [upstream container documentation](https://github.com/wallabag/docker)
for the image's bootstrap behavior. Inspect `docker-wallabag.service` and its
database/Redis companion units.
