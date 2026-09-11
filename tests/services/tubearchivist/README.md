# TubeArchivist fixtures

`config.nix` evaluates the actual service module, container graph, runtime SOPS
credentials, independent numeric directory ownership, exposure and snapshot
policy on both supported architectures.

The combined x86_64 startup/recovery check imports the exact configured TubeArchivist,
Elasticsearch and Redis images without network access in the VM. They wait for
the real application health endpoint and use small independent filesystem
markers. Recovery makes one shipped snapshot/Borg backup, erases
the owned roots and Elasticsearch volume, restores them, then checks readiness
and the markers. Redis remains a disposable cache.

No account, search, playback, ingestion, download, repeated lifecycle, failure
matrix, upgrade or ARM runtime behavior is claimed. Historical engine-only
evidence is recorded in the service guide and support matrix; it is not a
maintained test.
