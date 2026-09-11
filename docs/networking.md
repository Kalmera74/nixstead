# Networking, proxy, DNS, and Homepage

Networking integrations are derived from typed host endpoints and resolved
service-registry metadata. A service's final `domain`, `ip`, and `port` values
feed the generated consumers.

## Base networking

The shared system module enables NetworkManager and OpenSSH. The SSH port comes
from `nixstead.host.ports.ssh` and is applied to both the sshd listener and firewall.

```nix
nixstead.host = {
  network = {
    baseDomain = "home.arpa";
    lan = "192.168.1.20";
  };
  ports.ssh = 22;
  ssh = {
    authorizedKeys = ["ssh-ed25519 AAAAC3... admin@example"];
    passwordAuthentication = false;
    rootLogin = "no";
  };
};
```

Authorized keys are installed for `nixstead.host.user`. Password authentication also
controls keyboard-interactive authentication so disabling it does not leave a
second PAM password path enabled. Keys are optional: use `authorizedKeys = []`
with `passwordAuthentication = true` for password-only SSH access.

Most locally hosted services default their IP to `nixstead.host.network.lan`.

Domain-aware registry services combine their service subdomain with
`nixstead.host.network.baseDomain`, which defaults to the residential special-use
domain [`home.arpa`](https://www.rfc-editor.org/info/rfc8375) defined by RFC
8375. For example, Radarr defaults to `radarr.home.arpa` and Jellyfin defaults
to `watch.home.arpa`. A host can change all derived names:

```nix
nixstead.host.network.baseDomain = "lab.example.com";
```

An explicit service setting such as
`nixstead.services.media.jellyfin.domain = "media.example.net"` overrides the
derived hostname for that service only.

## Firewall generation

`modules/services/registry-integrations.nix` selects enabled services with a
firewall policy and collects:

- the service's resolved primary port;
- static TCP ports;
- host-level HTTP/HTTPS ports; and
- static UDP ports.

Ports are de-duplicated and then rendered according to each service's resolved
exposure class. The safe default is `loopback`, which opens no host firewall
port and makes configurable application listeners bind to `127.0.0.1`.

The available classes are:

| Class | Firewall behavior | Listener behavior |
| --- | --- | --- |
| `loopback` | No inbound firewall rule | Binds to `127.0.0.1` when supported |
| `lan` | Selected LAN interface and/or source CIDRs | Native listeners use the firewall; containers publish on `network.lan` |
| `tailnet` | `tailscale0` by default, optionally with source CIDRs | Native listeners use the firewall; containers publish on `network.tailscale` |
| `public` | Global allowed-port list | Binds to all addresses |

Set a class per service under `nixstead.host.network.exposure.services`. LAN and
tailnet selectors are host-level because multiple services commonly share the
same trust boundary:

```nix
nixstead.host.network.exposure = {
  services = {
    nginx = "lan";
    redis = "tailnet";
    grafana = "public"; # explicit unrestricted opt-in
  };

  lan = {
    interfaces = ["enp3s0"];
    sourceNetworks = ["192.168.1.0/24"];
  };

  # Defaults to interfaces = ["tailscale0"].
  tailnet.sourceNetworks = ["100.64.0.0/10"];
};
```

`nixstead.host.network.exposure.default` is a nullable host-wide override. Leave it
unset to keep the registry's safe loopback defaults; setting it is a deliberate
bulk policy, useful for a dedicated trusted-LAN host. Per-service values take
precedence over the host-wide override.

When both interfaces and source networks are present, packets must match both.
Source-network filtering enables the NixOS nftables firewall backend. A `lan`
service must have at least one LAN interface or source network; tailnet service
selection defaults to the `tailscale0` interface. Because OCI port publishing
bypasses the normal host input firewall, scoped container ports bind to the
corresponding host address and CIDR policy is repeated in an earlier nftables
forward hook. LAN/tailnet container exposure therefore also requires
`network.lan`/`network.tailscale`, respectively.

Changing a registry-backed service port therefore updates its standard
firewall rule automatically. It does not broaden the selected exposure:

```nix
nixstead.services.arr.radarr.port = 7879;
```

Nginx itself also defaults to `loopback`. Expose `nginx` as `lan`, `tailnet`, or
`public` to make generated proxy endpoints reachable across that boundary.

The setup wizard makes this choice explicit for generated hosts. LAN access
requires at least one interface or trusted source CIDR. Tailnet access enables
Tailscale and targets `tailscale0`. Public exposure requires a separate warning
confirmation and only opens the host firewall; router forwarding, public DNS,
and publicly trusted TLS remain the operator's responsibility.

## Nginx reverse proxy

Enable the platform service:

```nix
nixstead.services.nginx.enable = true;
```

For every enabled registry entry with proxy metadata, Nginx creates a virtual
host. Local services normally proxy to loopback. External integrations proxy to
their resolved service IP. WebSocket settings and special behavior such as the
Pi-hole `/admin/` redirect live in registry metadata or the renderer.

Example endpoint override:

```nix
nixstead.services.media.jellyfin = {
  domain = "watch.home.arpa";
  port = 8096;
};
```

The generated proxy becomes available at
`https://watch.home.arpa` when DNS resolves that name to the Nginx host.

## Local TLS

When Nginx is enabled, the certificate service creates:

- a local CA key and certificate under `/var/lib/nginx/local-ca/`; and
- a key/certificate pair for each configured service domain under Nginx's local
  TLS directory.

The generated CA keeps its private key and renews its self-signed certificate
with the same key before expiry. Service certificates are replaced when they
are missing, invalid, signed by a different CA, use the wrong domain/key, or
enter their renewal window. A persistent daily systemd timer performs the
check and gracefully reloads Nginx only when managed certificate material
changed. The CA signing key is `0600 root:root`; only leaf keys used by Nginx
are group-readable. The defaults are a 10-year CA, 825-day service
certificates, and a 30-day renewal window:

```nix
nixstead.services.nginx.ca = {
  validityDays = 3650;
  certificateValidityDays = 825;
  renewBeforeDays = 30;
};
```

For a host with `nixstead.host.user.enable = true`, the public CA certificate is also
copied to `~/.local/share/nixstead/<hostname>-nginx-ca.crt`, owned by that user
and readable without root access. The parent directory comes from
`nixstead.host.user.generatedFilesDirectory`. Set `homeCertificateFile = null` to
disable the copy or set it to another absolute destination. Client devices must
trust this certificate to avoid browser warnings. Never distribute
`/var/lib/nginx/local-ca/ca.key`.

After publishing the certificate in the common directory, activation removes a
matching legacy `~/<hostname>-local-ca.crt` copy. It never removes a different
file at that legacy path.

### Using an existing CA

Supply an existing CA as absolute runtime paths:

```nix
nixstead.services.nginx.ca = {
  certificateFile = "/etc/nixstead-ca/root-ca.crt";
  privateKeyFile = "/run/secrets/nixstead-ca-key";
};
```

Both options must be set together. They intentionally accept strings rather
than Nix path literals so the private key is never copied into the Nix store.
Private-key paths under `/nix/store` are rejected, including paths introduced
by interpolating a Nix path into a string.
The certificate service verifies that the files form a valid CA/key pair,
copies only the public certificate into its managed/public locations, and uses
the external key in place to sign service certificates. A SOPS secret path is
therefore suitable for `privateKeyFile`.

Service certificates still renew automatically when an external CA is used.
The external root itself remains user-managed; the timer warns as it approaches
the configured renewal window. Replacing the external certificate/key pair
causes incompatible service certificates to be reissued on the next check.

Certificates are local-network certificates, not public ACME certificates.

## Homepage

Enable Homepage with:

```nix
nixstead.services.homepage.enable = true;
```

The dashboard combines:

- registry-generated service cards; and
- explicit network-device cards.

Only enabled services with Homepage metadata receive a generated card. Widget
credentials are loaded from the `homepage` secret domain. Card URL and widget
target behavior are driven by the resolved service entry.

See the Homepage service group's
[README](../modules/services/homepage/README.md#homepage-widget-credentials)
for the complete key inventory, required permissions, and
application-specific acquisition steps.

Homepage-specific presentation and configuration are documented in the
Homepage service group's README. Static network cards remain explicit because
they represent host infrastructure rather than installed application services.

## Pi-hole local DNS synchronization

Enabled registry entries with `dns = true` provide the desired local domain
set. DNS mutation is disabled by default. Explicitly set
`nixstead.services.pihole.dnsSync.enable = true` to enable reconciliation.
When Pi-hole is enabled and its application password is available through
the Homepage SOPS secret (or `nixstead.services.pihole.dnsSync.credentialFile`), the
`nixstead-pihole-dns-sync.service` unit reconciles that set automatically on
boot and after deployed service toggles. It tracks exact ownership so disabled
services are removed without deleting unrelated manual records.

Enabling the Pi-hole dashboard/proxy or making its widget password available
does not opt in to DNS writes. Existing automatic-sync users must set the toggle
explicitly to retain that behavior.

The standalone sync tool remains available for diagnostics and defaults to
dry-run:

```bash
nixstead --host <host> dns sync
```

Apply changes only after reviewing output:

```bash
sudo nixstead --host <host> dns sync \
  --credential-file /run/secrets/pihole-web-password --apply
```

Without `--state-file`, `--prune-managed` removes records by matching the
desired DNS zones. This is broader than automatic state-tracked pruning and
should be reviewed carefully.

The Pi-hole integration must have a valid external IP/port. The sync script can
also accept explicit URL and credential flags; run `--help` for the current
interface.

## Tailscale

```nix
nixstead.services.tailscale = {
  enable = true;
  useRoutingFeatures = "server";
  advertiseRoutes = ["192.168.1.0/24"];
};
```

Valid routing modes are `none`, `client`, `server`, and `both`. Advertising a
subnet does not approve it in the Tailscale control plane; complete that step
through the account administration interface.

## External services

Pi-hole, Proxmox, and TrueNAS proxy targets use their corresponding
`nixstead.host.network` addresses. For example:

```nix
nixstead.host.network.proxmox = "192.168.1.10";
nixstead.services.proxmox.enable = true;
```

Enabling the integration does not install Proxmox. It exposes its configured
endpoint through this host's Nginx/Homepage integration.

## Troubleshooting

Inspect generated virtual-host keys:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.services.nginx.virtualHosts \
  --apply builtins.attrNames
```

Inspect open ports:

```bash
nix eval --json \
  path:.#nixosConfigurations.<host>.config.networking.firewall.allowedTCPPorts
```

For scoped rules, also inspect
`config.networking.firewall.interfaces` and
`config.networking.firewall.extraInputRules`.

Run runtime checks:

```bash
nixstead --host <host> --secrets-dir "$PWD/secrets" check runtime
```

If a proxy loops back into Nginx, verify that local-service registry entries use
the loopback proxy target and that the application itself listens on the
configured service port.
