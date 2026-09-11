# Redis

Redis provides an in-memory cache and key-value store. Nixstead runs the native
Redis server, binds it through the exposure policy, disables the default user,
and installs a SOPS-generated ACL user with full permissions.

## Enable and configure

```nix
nixstead.services.dev.redis = {
  enable = true;
  port = 6379;
};
```

Redis is a TCP service rather than a browser UI. Generate the shared development
credential branch with `nixstead --host <host> credentials bootstrap devdb`.

## Credentials

```bash
sudo cat /run/secrets/devdb/redis/rootUser
sudo cat /run/secrets/devdb/redis/rootPassword
```

Use both values with an ACL-aware Redis client. Inspect `redis.service` and its
generated ACL template if authentication fails.

## RDB persistence and recovery

The standalone development service defaults to durable RDB persistence. Its
registry backup stops `redis.service` before copying the effective native state
directory, so pending writes are flushed by Redis. Restoration validates the
configured RDB filename with the selected native package's `redis-check-rdb`
before stopping a healthy service or replacing state. Missing or corrupt RDBs
are refused. ACL identities come from the separately retained encrypted SOPS
source; the data archive does not contain that identity source.

The dedicated smoke checks authenticated native PING with runtime SOPS
credentials and writes one key marker using the custom directory/RDB filename.
Recovery erases the state directory, runs one shipped Borg restore and reads
the original key. Credential rotation, extra data structures, failures and
restart/reboot matrices are outside this smoke. AOF and cache-only overrides,
replication, upgrades and dependent-application reconstruction remain separate
profiles.

Use `nixstead backup verify` before restoring Redis state. If Redis rejects an
RDB, keep the original file untouched and recover with the Redis version that
wrote it or from a compatible verified backup. Deleting an RDB is data loss and
is intentionally not automated by Nixstead.

The reduced clean-restore smoke passed on x86_64-linux with KVM in 72.09
seconds on 2026-09-09. This timing covers startup, one marker and one shipped
Borg backup/restore.

A single `service-redis-recovery` VM covers initial startup/readiness and
one clean backup/restore.
