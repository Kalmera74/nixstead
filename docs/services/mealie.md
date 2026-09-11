# Mealie

Mealie manages recipes, meal plans, and shopping lists. Nixstead runs the
native `mealie.service`, disables public signup, and sets the external base URL.

## Enable and configure

```nix
nixstead.services.productivity.mealie = {
  enable = true;
  domain = "mealie.home.arpa";
  port = 8188;
};
```

The state directory is the native, read-only option
`/var/lib/mealie`. Recipe data, groups, users, and integrations are managed in
the application.

## Initial credentials

Retrieve Mealie's upstream bootstrap account with:

```bash
nixstead --host <host> credentials show mealie
```

The pinned Mealie version no longer exposes supported settings to preseed this
login. Its defaults are `changeme@example.com` and `MyPassword`; change them
immediately. See
[Secrets and credentials](../secrets.md#find-and-retrieve-credentials) and
inspect `mealie.service` if the account or UI is unavailable.

## Recovery

The native SQLite profile owns `mealie.db`, generated `.secret` and
`.session_secret` keys, and the `recipes` tree under `/var/lib/mealie`.
Backups stop the application to capture those files together. Restore handles
the native systemd dynamic identity and refuses a missing database or generated
key before changing application state. Native `DATA_DIR` overrides outside the
fixed root are rejected.

The maintained x86_64 fixture checks native startup/readiness and one shipped
Borg backup/restore with an independent test-owned continuity marker. It erases
the declared application root and checks the marker after final readiness.
Business workflows, repeated lifecycle and failure matrices are outside this
smoke fixture. The combined startup/recovery check passed in 116.25 seconds.
Configuration is checked independently on x86_64 and aarch64.

```bash
nix build --no-link -L path:.#checks.x86_64-linux.service-mealie
```

PostgreSQL requires an additional SQL recovery policy and is not covered by this
SQLite snapshot. Native credential files that override database/path settings,
mount outages, remote imports, SMTP/OIDC and cross-version upgrades are also
unverified. ARM currently has configuration checks only.
