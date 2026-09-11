# Home Assistant

Home Assistant provides local home automation. Nixstead runs the native
`home-assistant.service`, enables the default integration set, trusts only the
loopback reverse proxy, and stores state in the configured directory.

## Enable and configure

```nix
nixstead.services.homeassistant = {
  enable = true;
  domain = "homeassistant.home.arpa";
  port = 8123;
  paths.dataDir = "/var/lib/hass";
};
```

Integrations and automations created in the UI are application state. YAML
configuration lives under `paths.dataDir`; changing the path does not migrate
the existing database or configuration.

## Initial credentials

Open `https://homeassistant.home.arpa` and complete onboarding to create the
first owner account. Nixstead does not know or store that password. Inspect
`home-assistant.service` and `journalctl -u home-assistant`.

## State and recovery boundary

The native state directory owns local owner/authentication storage, application
helpers and integration settings under `.storage`, application-managed YAML
automations and the default SQLite recorder (`home-assistant_v2.db`). Stop the
service before staging the entire directory. Declarative `configuration.yaml`
is recreated from the selected Nix configuration at startup; retain that source
and the same package profile separately from mutable application state.

The registry policy requires common configuration, core owner/authentication
and onboarding storage before a restore can mutate live state. When native
`recorder.db_url` is omitted, it also requires `home-assistant_v2.db`. When native
`homeassistant.auth_providers` is omitted or explicitly contains only
`{ type = "homeassistant"; }`, it requires the local password-provider store.
Custom recorder URLs and other provider selections do not require those default
files, so their absence does not prevent archiving the remaining native state.

Omitting a default-file requirement does not add an external backup mechanism.
An external recorder or relocated SQLite file needs its own coordinated state
policy; alternate providers may require an independently recoverable identity
service or encrypted credentials. Full-directory snapshots include any such
files already located inside the state directory, but the dedicated recovery
scenario covers only the default local-owner/SQLite profile. Mixed or alternate
provider configurations, explicit recorder URL overrides and their dependencies
remain outside its recovery evidence.

The dedicated smoke starts the minimal native software profile, creates only
its initial owner to materialize authentication/onboarding stores, and writes a
small file marker. The password is generated into a disposable SOPS source
inside the VM. Recovery erases the native directory, runs one shipped Borg
restore, then checks HTTP readiness and the marker. Automations, recorder
queries, login/session continuity and lifecycle matrices are outside this smoke.

All 24 configuration assertions passed on both architectures.

The software profile omits automatic hardware discovery. Native onboarding can
schedule bundled cloud/media integration flows; their optional dependencies and
remote behavior are outside this minimal profile's assertions. USB/radios,
vendor clouds, external databases, upgrades and ARM execution remain unverified.
See the [support matrix](../support-matrix.md) for published execution evidence.

The reduced clean-restore smoke passed on x86_64-linux with KVM in 68.63
seconds on 2026-09-09, including initial-owner setup, HTTP readiness, one marker
and one shipped Borg backup/restore.

A single `service-homeassistant-recovery` VM covers initial startup/readiness and
one clean backup/restore.
