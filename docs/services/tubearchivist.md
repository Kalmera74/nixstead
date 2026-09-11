# TubeArchivist

TubeArchivist archives YouTube media and metadata. Nixstead runs hardened,
digest-pinned application, Redis, and Elasticsearch containers and mounts cache
state separately from archived media.

## Enable and configure

```nix
nixstead.services.media.tubearchivist = {
  enable = true;
  domain = "tube.home.arpa";
  port = 8183;
  paths = {
    dataDir = "/var/lib/tubearchivist";
    mediaDir = "/mnt/media/youtube";
  };
};
```

Generate the TubeArchivist username, password, and Elasticsearch password with
`nixstead --host <host> credentials bootstrap tubearchivist` before activation.

## Initial credentials

Open `https://tube.home.arpa`. Read the configured login only on the host:

```bash
sudo cat /run/secrets/tubearchivist/username
sudo cat /run/secrets/tubearchivist/password
```

Inspect `docker-tubearchivist.service`, `docker-tubearchivist-es.service`, and
`docker-tubearchivist-redis.service`.

## Recovery boundary

TubeArchivist recovery combines the configured application/cache directory, the
configured video directory and an Elasticsearch native snapshot of `ta_*`
application indices. The shipped backup helper stops the application and Redis,
keeps `docker-tubearchivist-es.service` alive for its snapshot, then stops the
companion database before staging files. The archive's database artifact is
`database-dumps/tubearchivist.tar`; old backups without it are incomplete.

The adapter creates a fresh repository under
`/usr/share/elasticsearch/data/nixstead-snapshots`, separate from TubeArchivist's
own snapshot repository. It requires a complete snapshot, unregisters the
repository before copying it, and bundles every repository file with checksums.
It never archives the raw Elasticsearch node data directory. This follows
[Elasticsearch 8.19's snapshot requirement](https://www.elastic.co/guide/en/elasticsearch/reference/8.19/snapshot-restore.html)
and [repository backup rules](https://www.elastic.co/guide/en/elasticsearch/reference/8.19/snapshots-register-repository.html).

Restore uses the existing explicit `--apply --restore-databases` flow. Before
changing application files, the helper refuses missing/corrupt repository files,
unsafe archive entries and missing application-index metadata. The adapter then
starts Elasticsearch, waits for primary-shard recovery, imports the repository
while unregistered and registers it read-only. It checks the snapshot's index
list before replacing only the named
application indices. It preserves unrelated indices, global state and the
Elasticsearch security database. Restored application directories retain the
configured existing account or numeric UID fallback and the shared media group,
matching initial directory creation. Runtime credentials come from the configured
container environment and stay out of host arguments and diagnostics. Preserve
the encrypted SOPS document and decryption keys separately.

This adapter requires the exact archived Elasticsearch version. A mismatch or
runtime failure leaves affected application units stopped after file restoration;
it does not claim rollback of a partially completed restore. Recovery across
Elasticsearch versions needs its own tested migration.

Redis is explicitly disposable: persistence is disabled, and the container no
longer mounts the old `tubearchivist-redis-data` volume. That volume is left
untouched. The policy treats Redis caches and active-task coordination as
reconstructable; indexed queued-video records are included in Elasticsearch.
Reconstruction of populated application queues remains unverified. Drain active
downloads before backup/recovery, and inspect/requeue interrupted jobs afterward. The
policy does not promise preservation of an active Redis job or exactly-once
processing. [TubeArchivist documents Redis as its queue/cache dependency and
Elasticsearch as the metadata and download-queue owner](https://docs.tubearchivist.com/installation/docker-compose/).

The application smoke imports all three exact production image digests, reaches
`/health`, and writes an independent marker in each configured filesystem root.
It erases those roots and the Elasticsearch volume before one clean encrypted
Borg restore, then checks application readiness and both markers. Redis remains
disposable. This does not claim populated search/video/account recovery,
interrupted jobs, repeated reboots, external downloads, upgrades or ARM runtime.

The reduced production-image x86_64 smoke passed in 627.89 seconds with
TubeArchivist 0.5.10, Elasticsearch 8.19.0 and Redis 7.4.10. Offline image import
took roughly 300 seconds of that run; the shipped backup completed in 41.96
seconds and clean restore in 101.24 seconds before final application readiness.
No application workflow or repeated lifecycle loop was included. The same
configuration checks build on x86_64 and strictly evaluate on aarch64.
