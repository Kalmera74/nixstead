# Open WebUI

Open WebUI is the browser interface for local AI models. Nixstead runs the
native service and connects it to local Ollama by default.

## Enable and configure

```nix
nixstead.services.localai.openwebui = {
  enable = true;
  domain = "ai.home.arpa";
  port = 8081;
};
```

For an external backend, disable the local Ollama child and set:

```nix
nixstead.services.localai.openwebui.ollamaUrl = "http://ollama.internal:11434";
```

The URL must use HTTP or HTTPS. Models are managed by Ollama rather than stored
by Open WebUI.

## Initial credentials

By default, open `https://ai.home.arpa`; the first account created through
onboarding is the administrator. Set `environmentFile` to a SOPS template with
`WEBUI_ADMIN_EMAIL` and `WEBUI_ADMIN_PASSWORD` to preseed that administrator
instead. Retrieve the configured values or onboarding instruction with:

```bash
nixstead --host <host> credentials show openwebui
```

See [Secrets and credentials](../secrets.md#find-and-retrieve-credentials) and
inspect `open-webui.service` for application or backend-connection failures.
Regular users need an administrator-configured model read grant; the pinned
version initially exposes unconfigured backend models only to administrators.

## State and recovery boundary

The native SQLite profile owns the entire `services.open-webui.stateDir`
(default `/var/lib/open-webui`). This includes `data/webui.db`, conversations,
accounts, uploads and vector state. The pinned 0.11.3 CLI creates
`.webui_secret_key` in its working directory when `WEBUI_SECRET_KEY` is absent;
the native working directory is the state root. Archiving only `data/` would
omit this key. See the [pinned CLI source](https://github.com/open-webui/open-webui/blob/v0.11.3/backend/open_webui/__init__.py).

The registry policy stops `open-webui.service` before staging the complete root.
With no native `DATABASE_URL`, `DATA_DIR` or environment-file override, it requires
`data/webui.db`. With no native `WEBUI_SECRET_KEY` or environment-file override,
it also requires `.webui_secret_key` before restoring any live state. Restore
uses DynamicUser ownership handling; systemd assigns the runtime identity when
the service starts. Preserve
the encrypted source and recipient identities for an `environmentFile`, including
any externally supplied key. The file's runtime contents are not imported into
Nix or automatically copied into this archive. Model weights belong to the model
server or the model storage owner.

This policy covers the native local SQLite layout. An environment file is opaque
to evaluation and can override database, data-directory and key settings; its
presence therefore omits these default-file requirements. That omission does not
add recovery of any external state. A redirected `DATA_DIR`, external database
or vector store, externally supplied key, or changed native identity/state-directory
setup needs its own consistent recovery policy.

The dedicated service smoke starts native Open WebUI 0.11.3 with offline model
settings and an explicit backend URL, then checks HTTP health and a small state
marker. Recovery erases its state root, runs one shipped Borg restore and checks
health and the marker. No model is downloaded or executed by this service smoke.
Accounts, chats, uploads, inference, backend outage and restart/reboot matrices
are outside its maintained scope.

All 28 configuration assertions passed on both architectures. External stores/keys, environment-file
profiles, ARM execution and upgrades remain unverified.

The reduced clean-restore smoke passed on x86_64-linux with KVM in 371.71
seconds on 2026-09-09. The timing covers native startup, HTTP health, one marker
and one shipped Borg backup/restore, without inference or application workflows.

A single `service-openwebui-recovery` VM covers initial startup/readiness and
one clean backup/restore.
