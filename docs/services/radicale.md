# Radicale

Radicale provides CalDAV calendars and tasks and CardDAV contacts. Nixstead runs
the native NixOS service with bcrypt authentication and private per-user
collections. Its small web interface manages collections; use a calendar or
contacts client for everyday editing. See the [upstream documentation](https://radicale.org/v3.html).

## Enable and connect

```nix
nixstead.services.productivity.radicale = {
  enable = true;
  domain = "radicale.home.arpa";
  port = 5232;
  paths.dataDir = "/var/lib/radicale";
};
nixstead.services.nginx.enable = true;
nixstead.services.homepage.enable = true;
```

The productivity parent and `full` preset select Radicale. Explicitly set
`nixstead.services.productivity.radicale.enable = false` to exclude it.

The backend listens on loopback by default. With Nixstead nginx enabled, open
`https://radicale.home.arpa/` or use that URL for CalDAV/CardDAV discovery.
The proxy redirects both `/.well-known/caldav` and `/.well-known/carddav` to `/`.
Clients can also use `https://radicale.home.arpa/admin/` for the generated
account, or a collection URL copied from the web interface. Resolve the domain
to the host and trust Nixstead's local CA on each client, or configure a trusted
certificate through the [nginx options](nginx.md).

## Credentials and multiple users

On first startup, Nixstead creates the user `admin` with a random password in
`<dataDir>/admin-password` and a bcrypt hash in `<dataDir>/users`. Both files
are mode `0600` and credentials are retained across restarts. The account has
access to its own collections, without server-wide administration privileges.

```bash
sudo cat /var/lib/radicale/admin-password
```

Use your configured `paths.dataDir` when reading the generated password.
`nixstead --host <host> credentials show radicale` also displays these setup
instructions.

For chosen passwords or multiple users, set `usersFile` to a runtime bcrypt
htpasswd file. Generate each entry using an interactive password prompt:

```bash
htpasswd -nB alice
```

Place the resulting `alice:<bcrypt-hash>` line in the encrypted host SOPS file
under `radicale.users`; use a YAML block scalar for multiple lines. Provision
`htpasswd` from the Nixpkgs `apacheHttpd` package if needed. Keep the hashes out
of Nix configuration and the repository's plaintext schema file.

```nix
{ config, ... }: {
  sops.secrets."radicale/users" = {
    restartUnits = ["radicale.service"];
  };
  nixstead.services.productivity.radicale.usersFile =
    config.sops.secrets."radicale/users".path;
}
```

This uses the host's existing [SOPS configuration](../secrets.md).
Systemd loads the file as a service credential, so the original can remain
root-readable. Setting `usersFile` disables generation and replaces the account
list; an old generated password no longer controls login. Update the encrypted
file to add users or change passwords. Preserve usernames to retain access to
their existing collections.

## Storage and verification

Collections live under `<dataDir>/collections`. The registry backup policy stops
`radicale.service` and saves the state directory, including generated credentials.
An external `usersFile` remains owned by its encrypted configuration; preserve
that file and the decryption identity separately. Native storage overrides are
included in backup paths; provision their directories and permissions separately.
Inspect the service with `journalctl -u radicale.service`.

The configuration suite checks selection, exposure, proxy/card integration,
credential overrides and backup metadata. The x86_64 recovery fixture checks
native readiness, authenticated DAV discovery, anonymous denial and one clean
Borg restore with credential and file-marker continuity. It does not establish
calendar/contact synchronization, external-client compatibility, HTTPS discovery,
runtime SOPS rotation, ARM runtime or cross-version upgrades. Execution evidence
is recorded in the [support matrix](../support-matrix.md).

```bash
nix build --no-link -L path:.#checks.x86_64-linux.service-radicale
```
