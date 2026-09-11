# Central service registry

The registry is the source of truth for service identity and repeated
integration metadata. `modules/services/registry.nix` is its stable aggregate
entrypoint; stack-aligned definitions and standalone-service metadata live
under `modules/services/registry/`.
This prevents service names, endpoints, health units, secrets, and backup
mappings from drifting across unrelated files without recreating one large
catalog file.

The registry does not replace service implementation modules. It describes
uniform facts; concrete modules still own behavior that cannot be rendered
generically.

## Static and resolved views

The static registry is available to flake consumers as:

```nix
nixstead.lib.serviceRegistry
```

Inside an evaluated NixOS system, the read-only option:

```nix
config.nixstead.serviceRegistry
```

contains every static entry plus:

- `enabled` — the final value at the entry's enable path; and
- `exposure` — the host-resolved network exposure class; and
- `settings` — the final attrset at its service option path.

This resolved view lets renderers and scripts use host overrides without
reimplementing Nix option resolution.

## Entry anatomy

A typical entry resembles:

```nix
jellyfin = mkService {
  name = "Jellyfin";
  optionPath = ["media" "jellyfin"];
  defaults = {
    subdomain = "watch";
    port = 8096;
  };
  firewall = true;
  proxy = localProxy;
  homepage = /* card metadata */;
  health = health "jellyfin.service";
  backup = backup "jellyfin" "jellyfin.service" "jellyfin" "jellyfin";
  setup = setup "media-core" 110 ["media-server" "full"];
};
```

## Fields

| Field | Purpose |
| --- | --- |
| `name` | Human-readable service label |
| `optionPath` | Path below `nixstead.services` containing service settings |
| `enablePath` | Optional different path used to resolve enabled state |
| `defaults` | Shared subdomain, canonical domain, port, and host-network source defaults |
| `local` | Whether listeners run on this host; external integrations set this false |
| `listeners` | Application TCP/UDP listeners derived from service settings, host ports, or static ports |
| `firewall` | Primary/static TCP and UDP exposure |
| `exposure` | Safe default exposure class for entries with firewall metadata |
| `containerPublished` | Whether the host port uses OCI publishing and needs forward-path protection |
| `proxy` | Upstream type, scheme, websocket, and special-vhost behavior |
| `homepage` | Section, order, card text, URL, and widget metadata |
| `health` | Unit, protocol, endpoint suffix, host port, or external check |
| `dns` | Whether the resolved domain participates in DNS synchronization |
| `ociImages` | Managed image components with repository, role, and digest-pinned default metadata |
| `secrets` | Required secret-domain names |
| `credentials` | User-facing SOPS, runtime-file, configured-value, bootstrap-default, or first-run credential sources |
| `backup` | Directory, unit, and fallback owner/group |
| `setup` | Wizard group, ordering, label, preset membership, and prompts |

Not every service needs every field. `null` means the service does not
participate in that integration.

For domain-aware services, registry fragments declare `defaults.subdomain`.
`mkService` exposes a canonical `defaults.domain` below `home.arpa` in the
static registry, while `serviceOptionFromRegistry` resolves the actual service
default from `nixstead.host.network.baseDomain`. This keeps the static metadata
serializable while allowing every host to select its own DNS suffix.

## Different option and enable paths

Some services need explicit paths:

- Swaparr is a child service at `nixstead.services.arr.swaparr`.
- Tdarr settings live at `nixstead.services.media.tdarr`, while server and node state
  use separate child flags.
- Samba is controlled by `nixstead.services.nas.samba.enable` but shares the NAS
  settings attrset.

Use `enablePath` and `setup.optionPath` for these cases rather than special-case
logic in every consumer.

## Registry consumers

### Nix module consumers

- `serviceOptionFromRegistry` defines consistent ordinary service options.
- `core/options.nix` rejects missing listener ports and TCP/UDP collisions among
  enabled local services.
- `presets.nix` applies registry preset membership.
- `registry-integrations.nix` renders declared ports into loopback, interface,
  source-network, tailnet, or global firewall policy.
- `nginx/registry-proxies.nix` generates TLS virtual hosts.
- `homepage/services-registry.nix` generates dashboard cards and widgets.

### Script consumers

- The Python setup application (launched by `setup.sh`) builds service
  checklists and writes option overrides.
- `healthcheck.sh` determines required secrets.
- `health-homelab.sh` checks enabled units and endpoints.
- `dev-healthcheck.sh` inspects development services.
- `generate-credential-files.sh` derives required credential domains.
- `service-credentials.sh` lists and explicitly retrieves registered credential sources.
- `sync-pihole-local-dns-from-nginx.sh` derives DNS records.
- `container-images.sh` discovers components, repositories, roles, and defaults
  for host-specific upgrades and downgrades.
- backup and restore scripts derive directories, units, and ownership.

All scripts evaluate the selected host rather than using only static metadata.

## Adding a service

1. Add a registry entry to the matching stack fragment under
   `modules/services/registry/`, with only the integrations the service
   supports. Add a new fragment to the aggregate entrypoint only when no
   existing category fits.
2. Define its option using `serviceOptionFromRegistry` where possible.
3. Add the concrete module under the appropriate service stack.
4. Import that module from its stack wrapper or orchestrator.
5. Add placeholder keys to `secrets/secrets.example.yaml` and runtime sops-nix
   declarations if the registry declares a new secret domain.
6. Add custom renderer code only if the generic metadata cannot express the
   required behavior.
7. Update the service catalog documentation.
8. Run shell syntax checks and `nix flake check path:.`.

Every configurable registry port must be passed to the concrete NixOS service
or container. Typed runtime paths belong to the concrete `nixstead.services` stack
option, not registry defaults or host-level native `services.*` assignments.
The implementation maps wrapper paths to its backend. Add API checks against
the application's effective configuration; checking only Nginx, Homepage, or
firewall output does not prove that the application moved.

Shared constructors such as `mkService`, `localProxy`, and `setup` live in
`modules/services/registry/lib.nix`. Registry fragments are pure metadata
functions over those helpers; they must not import concrete service modules.

Example option definition:

```nix
options.nixstead.services.media.example =
  serviceOptionFromRegistry "example" {};
```

Example conditional implementation:

```nix
config = lib.mkIf config.nixstead.services.media.example.enable {
  services.example.enable = true;
};
```

## Design constraints

Backup metadata can resolve effective NixOS paths with `nativePathOption` and
`extraNativePathOptions`, and effective database names with `databaseNameOption`.
Use these when native defaults or overrides determine the real state location.
The primary archive slot stays first; extra native paths inside that primary
directory are already covered. Missing optional extra paths are omitted.

- Keep service-specific container behavior out of the registry; managed OCI
  identity, role, and default references are shared integration metadata.
- Use child toggles for integration state, not parent stack flags.
- Do not add the same service list to setup, Nginx, Homepage, or scripts.
- Keep host-specific values in `nixstead.host` or host configuration.
- Treat registry names and option paths as integration identifiers; changing
  them affects scripts and public host configuration.

## Inspecting registry data

Static metadata:

```bash
nix eval --json path:.#lib.serviceRegistry
```

Resolved host metadata:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.serviceRegistry
```

List enabled registry services with `jq`:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.nixstead.serviceRegistry \
  | jq -r 'to_entries[] | select(.value.enabled) | .key'
```
