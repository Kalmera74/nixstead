# ARR ntfy notification relationships

Nixstead can ensure a native ntfy notification entry in Sonarr, Radarr or Lidarr.
This uses each application's supported notification interface. It does not
provision an ntfy server or create a new service stack.

```nix
sops.secrets."ntfy/token" = {};
nixstead.services.arr.integrations.ntfy.sonarr = {
  enable = true;
  endpoint = "https://notifications.example.net";
  topics = ["media-health"];
  tokenFile = config.sops.secrets."ntfy/token".path;
  events = {onHealthIssue = true; onHealthRestored = true;};
};
```

The application must be enabled. Select topics, server and events explicitly.
The token is a runtime credential delivered only to this relationship. Creation
and configuration changes invoke the native connection test, which sends a
notification. Unchanged periodic runs do not send test messages.

Nixstead owns connection fields and explicitly declared event toggles in its
journal-identified entry. It preserves other entries and fields; disabling the
relationship leaves the entry in place. Dry runs show redacted field changes.
Rotate the supplied token file to update the application on the next run.
Because ARR masks saved tokens, an unannounced UI token edit cannot be detected
without sending another notification. The adapter avoids periodic test messages;
rotate the declared runtime token to recover this specific drift.

Runtime coverage uses real ARR APIs and a local HTTP notification fixture.
No external messages are sent by the repository tests.
