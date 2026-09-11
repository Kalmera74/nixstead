# SearXNG

SearXNG is a private metasearch engine. Nixstead runs the native
`searx.service`, generates its application secret locally, and exposes the
search UI through Nginx.

## Enable and configure

```nix
nixstead.services.productivity.searxng = {
  enable = true;
  domain = "search.home.arpa";
  port = 8191;
};
```

The fixed state directory `/var/lib/searxng` contains the generated environment
file. Search engines and preferences use the native service configuration; add
new supported options to the module rather than embedding plaintext secrets.

## Credentials

The current SearXNG UI has no login. The generated secret signs application
state and is not a user password. Inspect `searxng-bootstrap-secret.service`
and `searx.service` for startup errors.

## State and recovery boundary

The generated environment file is the only owned durable state in this profile;
search requests and the local Redis limiter cache are disposable. The service
backup policy stops SearXNG and archives `/var/lib/searxng`, requiring that
environment file before restore can mutate state. Preserve the Borg repository
and its encryption material together.

The combined x86 VM check intentionally stays small. It starts native SearXNG
against a deterministic local JSON engine, verifies one query, and runs one
encrypted backup and clean restore of the generated secret. It does not
establish public-engine compatibility, ranking, limiter, browser or failure
behavior.
