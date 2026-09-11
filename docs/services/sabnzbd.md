# SABnzbd

SABnzbd is an optional native Usenet downloader under
`nixstead.services.arr.sabnzbd`. It is excluded from presets. Its registry provides
setup selection, the `sab` proxy, Homepage card, health unit, required-state
backup policy and native exporter metadata. The package requires nixpkgs permission
for the `unrar` unfree redistributable dependency; Nixstead includes that narrow
permission only while SABnzbd is selected.

```nix
nixstead.services.arr = {
  sabnzbd.enable = true;
  storage = {root = "/data"; manageDirectories = true;};
  sonarr.enable = true;
  integrations.enable = true;
};
```

Declare mounts when the storage lives on another filesystem. The selected
Usenet layout is `storage.usenet.{root,incomplete,complete}`; category directories
live below `complete`. Shared media permissions and mount guards apply.
The generated client and category use runtime API authentication. An existing
nonempty queue blocks a managed category path change. Existing clients,
categories and server configuration are preserved.

Configure Usenet servers explicitly in the UI or use `sabnzbd.secretFile` pointing
to a SOPS runtime INI file, for example `config.sops.secrets."sabnzbd/settings".path`.
The native module receives it with `LoadCredential`. Never put server passwords
in `services.sabnzbd.settings`. When shared credentials are enabled, automatic
enrollment saves and delivers the canonical `sabnzbd/apiKey` before startup,
reusing existing SOPS or native keys. SABnzbd and its consumers share it. WebUI
authentication should be configured before exposing the application.

State defaults to `/var/lib/sabnzbd`; `paths.dataDir` controls the registry/native
path together. Backups require `sabnzbd.ini`. Inspect `sabnzbd.service`,
`nixstead-credential-sabnzbd.service` and the ARR status command.

## Dedicated smoke checks

The x86_64 service checks share one combined native ARR startup/recovery
fixture, so selecting several family members reuses one VM derivation.
They check service readiness, private runtime SOPS credentials, and one selected
shipped reconciliation. Stateful services get one encrypted Borg backup and
empty-state restore, followed by readiness and an independent file marker in
each selected metadata root. Media acquisition/import, existing queues and
libraries, repeated lifecycle, and incomplete-input matrices are outside this
fixture. Source and download bytes remain separately owned.

The combined x86_64 startup/recovery check passed in 641.19 seconds in the
recorded run. Configuration is checked independently for each service on x86_64
and aarch64.
