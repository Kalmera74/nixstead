# authentik

authentik provides identity, SSO, and proxy-provider workflows. Nixstead runs
native server and worker units, creates a local PostgreSQL role/database, and
loads the application signing secret from SOPS.

## Enable and configure

```nix
nixstead.services.authentik = {
  enable = true;
  domain = "auth.home.arpa";
  port = 9000;
  paths.dataDir = "/var/lib/authentik";
};
```

Worker, metrics, and internal HTTPS ports have typed overrides but normally
remain on their registry defaults. Generate the signing key with
`nixstead --host <host> credentials bootstrap authentik`; it is not a login password.

## Initial credentials

After first activation, open
`https://auth.home.arpa/if/flow/initial-setup/` and set the password for the
initial `akadmin` account. Inspect `authentik-database-setup.service`,
`authentik-server.service`, and `authentik-worker.service`.

The SOPS key is a persistent application identity secret. Missing or unreadable
key material refuses server and worker startup. Replacing it is not an account
password reset: existing sessions and signed file links depend on that key.
Keep its encrypted source and age identity available when recovering the service.

Database setup and both application roles use the effective native PostgreSQL
port. Repeated setup preserves the existing application database; it creates the
owned role/database only when absent.

## State and recovery boundary

The registry stops both native units and combines a logical export of the
`authentik` PostgreSQL database with `paths.dataDir`. The selected local file
backend stores uploaded media beneath `media/public` in that directory. Database
state includes users, passwords, providers, signing certificates/keys, tokens,
and sessions. Runtime SOPS files are recovered from their separately retained
encrypted source, not from a newly generated signing secret.

The native certificate watcher uses the owned `certs` subdirectory of the same
state root. Files placed there for discovery are included in its archive;
the module creates that directory before starting the worker.

The PostgreSQL export is required before restore can modify a destination.
Uploaded file names are variable and an installation may have no media, so
generic archive preflight does not require one particular image. Application
verification must check that original referenced media remains accessible.
Restoring identity records alone does not establish complete media recovery.

## Dedicated checks

The fixture selects native authentik 2026.5.6 with custom application/internal
listeners, local storage, and a custom PostgreSQL port. A private runtime SOPS
environment bootstraps a disposable administrator. The combined smoke requires both
native units, their health endpoints, the bootstrap API, and private credential
files.

Recovery checks Nixstead's wiring with explicit test-owned SQL and file markers.
It erases the application database and state root, runs one shipped encrypted
Borg restore, and verifies readiness and both restored markers. This is a
backup/restore smoke check. Application identity/provider workflows, repeated
lifecycle, outage matrices, proxy interactions, and cross-version recovery are
outside its scope.

Configuration passed on x86_64 and aarch64. The combined x86_64 startup and
backup/restore check passed in 449.78 seconds with KVM.
That run included an additional readiness check after the
backup's restart; the current helper omits that wait and retains final readiness.
