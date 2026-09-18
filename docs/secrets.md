# Secrets and credentials

Nixstead uses [sops-nix](https://github.com/Mic92/sops-nix) to keep plaintext
credentials out of Git, Nix evaluation, derivations, binary caches, and
world-readable `/nix/store` paths.

Each host has one encrypted document:

```text
secrets/<configurationName>.yaml
```

The encrypted YAML is safe to track. During activation, sops-nix decrypts only
the declared keys into root- or service-readable files below `/run/secrets`.
Services consume those files directly or through runtime-only templates. The managed
media credential broker receives one root-only decrypted document so missing keys
can remain pending during bootstrap; it delivers only selected values to each consumer.

## Threat model

This protects against accidental Git publication, copied repositories, Nix
store disclosure, remote builders, binary caches, old system generations, and
an unrelated unprivileged service reading another service's credentials.

It does not protect secrets after a live root compromise. Root can read the
host identity, `/run/secrets`, process memory, and service credentials. Use full
disk encryption for powered-off disk theft, restrict service users, patch the
host, and rotate credentials after a root compromise.

## Enroll a host

The setup runtime contains `age`, `sops`, and `ssh-to-age`:

```bash
nix run path:.#nixstead -- --host <host> setup sops
```

The helper:

1. creates `~/.local/share/nixstead/sops-age-key.txt` if it does not exist;
2. derives a public admin recipient from that identity;
3. derives a public age recipient from
   `/etc/ssh/ssh_host_ed25519_key.pub`; and
4. writes a host-specific creation rule to `.sops.yaml`.

Only public recipients enter the repository. Back up the admin age identity in
a secure password manager or offline encrypted backup. The host keeps its
existing SSH private key root-only.

The setup wizard passes its selected identity to credential generation,
decryption, and preflight before the first activation. Nixstead also sets
`SOPS_AGE_KEY_FILE` to this common location for the managed user's login
sessions. When running the individual helpers manually before activation,
export it explicitly:

```bash
export SOPS_AGE_KEY_FILE="$HOME/.local/share/nixstead/sops-age-key.txt"
```

If the helper finds the legacy `~/.config/sops/age/keys.txt` identity, it moves
that same key into the common directory so existing recipients do not change.
The user module performs the same migration during activation for hosts that
upgrade without rerunning the helper.

For a public key in another location:

```bash
nixstead --host <host> setup sops \
  --ssh-public-key /path/to/ssh_host_ed25519_key.pub
```

If recipients change, replace the policy block and rewrap the existing data
key:

```bash
nixstead --host <host> setup sops --force
sops updatekeys --yes secrets/<host>.yaml
```

## Generate and edit credentials

Generate one domain or every credential branch required by enabled services:

```bash
nixstead --host <host> credentials bootstrap vaultwarden
nixstead --host <host> credentials bootstrap authentik
nixstead --host <host> credentials bootstrap homepage
nixstead --host <host> credentials bootstrap all
```

The generator prompts without echoing sensitive input, converts the result in
a private temporary directory, and updates only the selected encrypted YAML
branch. It refuses to replace an existing branch unless `--force` is supplied.

With shared media credentials enabled, one rebuild automatically enrolls and
delivers credentials before application startup. Existing SOPS values win; absent
values are imported from native application state or generated once and saved
encrypted before use. The host uses its enrolled age identity and the writable
source corresponding to `nixstead.secrets.sopsFile`. Encrypted edits are delivered
automatically within about a minute, with affected consumers restarted.

Conflicting Homepage/Swaparr copies require explicit source selection. Source,
decryption and malformed-key errors fail explicitly without replacing delivered
credentials. See [media credential operations](media-operations.md#canonical-sops-credentials)
for source configuration, manual opt-out, consolidation, rotation and inspection.

`configure-homepage-integrations.sh` still prompts for unrelated applications;
it writes encrypted values and leaves deployment to your next rebuild.

For direct editing:

```bash
sops secrets/<host>.yaml
```

Never create a decrypted copy inside the repository. If a temporary plaintext
export is unavoidable, keep it on a protected filesystem and remove it
immediately afterward.

The tracked [schema](../secrets/secrets.example.yaml) contains every supported
key with placeholders. It must never contain real credentials.

## Find and retrieve credentials

Use the registry-aware credential helper instead of searching service files or
printing the complete decrypted document:

```bash
nixstead --host <host> credentials list
nixstead --host <host> credentials show nextcloud
nixstead --host <host> credentials show sops:homepage/piholeApiKey
```

If `jq` or `sops` is not installed in the current shell, the helper
automatically re-launches itself through `path:.#setup-runtime`.

`list` never prints values. It lists credential-aware services and every scalar
key that is actually present in `secrets/<host>.yaml`, including keys not known
to the service registry. For managed ARR/Seerr/qBittorrent credentials, `show <service>` reveals the canonical
SOPS value and `--runtime` selects the deployed copy. For other services,
`show <service>` combines registered SOPS values,
Homepage integration secrets, configured usernames, known upstream defaults,
runtime-generated files, and first-run instructions. `show sops:<path>` reveals
one exact encrypted leaf. Both `show` forms deliberately print plaintext and
may need an age identity or `sudo` for a protected runtime file.

Nextcloud, Miniflux, ntfy, and Syncthing keep generating persistent random
bootstrap credentials when no file is configured. Open WebUI also accepts a
protected environment file for its supported admin bootstrap variables. These
options allow credentials to be chosen and retrieved before first activation.
For example:

```nix
{config, ...}: {
  sops.secrets."bootstrap/nextcloudAdminPassword".owner = "nextcloud";
  nixstead.services.productivity.nextcloud.adminPasswordFile =
    config.sops.secrets."bootstrap/nextcloudAdminPassword".path;

  sops.secrets."bootstrap/ntfyAdminPassword" = {};
  nixstead.services.dev.ntfy.adminPasswordFile =
    config.sops.secrets."bootstrap/ntfyAdminPassword".path;

  sops.secrets."bootstrap/syncthingGuiPassword".owner = "syncthing";
  nixstead.services.syncthing.guiPasswordFile =
    config.sops.secrets."bootstrap/syncthingGuiPassword".path;

  sops.secrets."bootstrap/minifluxUsername" = {};
  sops.secrets."bootstrap/minifluxPassword" = {};
  sops.templates."miniflux-admin.env".content = ''
    ADMIN_USERNAME=${config.sops.placeholder."bootstrap/minifluxUsername"}
    ADMIN_PASSWORD=${config.sops.placeholder."bootstrap/minifluxPassword"}
  '';
  nixstead.services.productivity.miniflux.adminCredentialsFile =
    config.sops.templates."miniflux-admin.env".path;

  sops.secrets."bootstrap/openWebuiEmail" = {};
  sops.secrets."bootstrap/openWebuiPassword" = {};
  sops.templates."open-webui-admin.env".content = ''
    WEBUI_ADMIN_EMAIL=${config.sops.placeholder."bootstrap/openWebuiEmail"}
    WEBUI_ADMIN_PASSWORD=${config.sops.placeholder."bootstrap/openWebuiPassword"}
  '';
  nixstead.services.localai.openwebui.environmentFile =
    config.sops.templates."open-webui-admin.env".path;
}
```

Add those example paths to the encrypted host document before using them. The
file options are intentionally generic, so an existing SOPS key or template can
be used without adopting these example names. Before first activation, use the
exact `show sops:bootstrap/...` selector because the `/run/secrets` files and
rendered templates do not exist yet; afterward, `show <service>` reads them.

For Homepage integrations, the service group's
[README](../modules/services/homepage/README.md#homepage-widget-credentials)
maps every schema key to the relevant application UI and required permissions.

## Host configuration

Hosts in this repository normally need only:

```nix
nixstead.secrets.enable = true;
```

The default file is `secrets/<configurationName>.yaml`. For a consumer flake or
another layout, set it explicitly:

```nix
nixstead.secrets = {
  enable = true;
  sopsFile = ./secrets/my-host.yaml;
};
```

The default decryption identity is the SSH Ed25519 host key:

```nix
nixstead.secrets.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
```

A dedicated identity is also supported:

```nix
nixstead.secrets.age.keyFile = "/var/lib/sops-nix/key.txt";
```

## External secrets directory

`NIXSTEAD_SECRETS_DIR` remains supported for an encrypted directory outside
the checkout. It must contain `<configurationName>.yaml`:

```bash
sudo env NIXSTEAD_SECRETS_DIR=/secure/nixstead-secrets \
  nixos-rebuild switch --impure --flake path:.#<host>
```

`--impure` is required only because evaluation reads the environment variable.
The decrypted values still never enter Nix evaluation or the store. With the
repository-default encrypted file, ordinary pure evaluation and rebuilds work.
Existing deployments may continue using `NIXCONFIG_SECRETS_DIR` as a deprecated
alias; new configuration and documentation should use `NIXSTEAD_SECRETS_DIR`.

## Operational guidance

- Give each host its own recipient so removing one host does not require
  replacing every machine identity.
- Give secrets the narrowest service owner possible. Nixstead's modules do
  this where a native service reads the file itself; root-only templates are
  used when systemd starts containers.
- Prefer native `passwordFile`/credential options and application `_FILE`
  variables. Container environment files avoid the Nix store but values can
  still be visible through privileged container inspection.
- Review `.sops.yaml` whenever hosts or administrators are added or removed.
- Rotate the affected credentials after recipient-key loss or host compromise.
- Back up the admin age identity separately from the encrypted repository.
