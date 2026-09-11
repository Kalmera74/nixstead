# Kavita

Kavita serves ebooks, comics, and manga. Nixstead runs `kavita.service` and
generates a private token-signing key before the application starts.

## Enable and configure

```nix
nixstead.services.media.kavita = {
  enable = true;
  domain = "kavita.home.arpa";
  port = 5000;
  paths.dataDir = "/var/lib/kavita";
  tokenKeyFile = "/var/lib/kavita/kavita-token-key";
};
```

Both path overrides are optional. Moving either path requires moving the
existing state deliberately. Add libraries and scanning rules through the UI.

## Initial credentials

Open `https://kavita.home.arpa` and create the administrator during onboarding;
the generated signing key is not a login password. For Homepage, create an Auth
Key under **User Settings > 3rd Party Clients**.

Inspect `kavita-token-key.service` and `kavita.service` when startup fails.

## State backup and smoke check

Backups follow the effective native application directory and service account.
The generated signing key is included when it lives beneath that root, as in
the default and smoke profiles. A key configured outside the application root
requires a separate backup; its parent directory is not recursively included.
Both the effective state path and signing-key directory participate in startup
mount ordering. Book and comic source libraries remain separately owned.

The pinned Kavita 0.9.0.2 x86_64 smoke passed in 108.05 seconds. It checks native HTTP readiness, a small state marker, and the
original signing-key hash after one clean encrypted Borg restore. It does not
exercise account/library workflows, reading progress, source-content recovery,
repeated reboots, detailed failure cases or upgrades. ARM configuration checks
do not establish ARM runtime support.
