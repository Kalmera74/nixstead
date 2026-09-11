# PostgreSQL

PostgreSQL is the relational database service used directly and by other
modules. Nixstead runs the native server and creates or updates a SOPS-managed
login superuser after startup.

## Enable and configure

```nix
nixstead.services.dev.postgresql = {
  enable = true;
  port = 5432;
};
```

The registry controls listener exposure. Application modules may also create
local databases and peer-authenticated roles. Generate administrator values
with `nixstead --host <host> credentials bootstrap devdb`.

## Credentials

```bash
sudo cat /run/secrets/devdb/postgresql/rootUser
sudo cat /run/secrets/devdb/postgresql/rootPassword
```

For local maintenance, `sudo -u postgres psql` uses the service account and
does not need the network password. Inspect `postgresql.service` for failures.

## Collation maintenance after libc or ICU updates

Check the recorded database versions:

```bash
sudo -u postgres psql -X -d postgres -c 'SELECT datname, datcollversion, pg_database_collation_actual_version(oid) AS actual FROM pg_database ORDER BY datname;'
```

If versions differ, save and verify a PostgreSQL backup, pause application
writers, and review the affected indexes and collations during a maintenance
window. The correct rebuild order depends on the database objects and
applications involved, so Nixstead does not automate this repair. Do not refresh
the recorded version merely to silence warnings: it does not rebuild or validate
affected objects. See PostgreSQL's
[collation maintenance guidance](https://www.postgresql.org/docs/16/sql-altercollation.html)
and [REINDEX documentation](https://www.postgresql.org/docs/16/sql-reindex.html).

## Dedicated service smokes

The combined smoke checks authenticated SQL readiness using runtime SOPS
credentials and writes one table marker in a separate application database. Recovery erases the custom cluster
directory, runs one shipped Borg restore and checks readiness and the original
row. Credential rotation, account/ownership matrices and repeated lifecycle
checks are outside this smoke.

The smoke excludes user-owned objects in the `postgres` maintenance database.
Restoring the full logical dump over a physical snapshot can fail when such
objects still depend on a role that the dump tries to recreate. Use a separate
application database for this tested profile; global dump ordering for custom
maintenance-database objects remains unresolved.

The reduced clean-restore smoke passed on x86_64-linux with KVM in 52.81
seconds on 2026-09-09, using the separate application-database marker.

A single `service-postgresql-recovery` VM covers initial startup/readiness and
one clean backup/restore.
