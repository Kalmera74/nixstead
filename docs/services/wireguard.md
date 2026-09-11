# WireGuard

`nixosModules.wireguard` exposes `nixstead.services.wireguard` independently of
ARR. The complete and services modules include it too. It provides ordinary
host tunnels through native NixOS wg-quick and isolated application namespaces
through the pinned VPN-Confinement dependency. The shared implementation is
`modules/services/wireguard.nix`; application adapters attach their services to
it and configure their own listeners.

The flake imports the namespace backend only with WireGuard, ARR, and the
complete service aggregates and presets. Unrelated public modules, including
`base` and `media`, do not import it. Importing the backend does not enable a VPN.

Both modes are opt-in. Enabling WireGuard alone creates no tunnels. Declare named
interfaces or namespaces in Nix; the setup wizard does not select a topology or
collect WireGuard private keys. Each declared entry defaults to enabled when
WireGuard is enabled and can be disabled with its own `enable = false`.

## Host tunnels

```nix
nixstead.services.wireguard = {
  enable = true;
  interfaces.work = {
    sopsSecret = "wireguard/work";
    # For incoming handshakes, explicitly open the port used by ListenPort:
    # allowedUDPPorts = [51820];
  };
};
```

The encrypted `wireguard/work` value contains a complete wg-quick configuration
with its interface addresses, private key and peers. Peer AllowedIPs determine
the host's routes; DNS follows native wg-quick behavior. This supports normal
client or peer configurations. Host tunnels do not receive the application
namespace's firewall confinement. Full-tunnel host routing and a VPN server's
forwarding, NAT and access policy require deliberate configuration.

Inspect `wg-quick-work.service`. Set `autostart = false` to start it manually.
Interface names must start with a letter and contain at most 15 letters, digits,
underscores or hyphens. The module opens no incoming host ports by default.

## Isolated application tunnels

```nix
nixstead.services.wireguard = {
  enable = true;
  namespaces.apps = {
    sopsSecret = "wireguard/apps";
    services = ["my-worker"]; # Existing systemd unit, without .service
    # Optional namespace ports reachable from its host bridge address:
    # hostAccess.tcpPorts = [9000];
  };
};
```

The application must be configured separately. Its network namespace and DNS
are supplied by the shared module. Stopping the namespace stops attached
services; restarting it restarts them. `autostart = false` suppresses the
namespace's boot start; an enabled application can still start it as a dependency.
A service can belong to only one namespace.

Namespace names must start with a letter and contain at most seven letters,
digits, underscores or hyphens because the backend derives Linux interface
names from them. The default host bridge uses `192.168.241.1`, with namespace
address `192.168.241.2`; IPv6 equivalents are `fd93:9701:241::1` and
`fd93:9701:241::2`. Every additional namespace needs distinct /24 and /64 networks:

```nix
nixstead.services.wireguard.namespaces.other = {
  configFile = "/run/credentials/other.conf";
  namespaceAddress = "192.168.242.2";
  bridgeAddress = "192.168.242.1";
  namespaceAddressIPv6 = "fd93:9701:242::2";
  bridgeAddressIPv6 = "fd93:9701:242::1";
};
```

Also check for overlap with your host, LAN and provider routes. Each namespace
has a default-deny incoming policy and blocks new outgoing connections through
its host bridge. DNS is routed through the tunnel. Host access rules open only
selected namespace ports to its bridge address; they do not publish a host port
or create DNAT rules. Keep application authentication enabled. Containers and
remote machines need an explicitly configured proxy or access path.

This backend expects a provider configuration with Address, DNS, one peer
Endpoint and full-tunnel IPv4/IPv6 AllowedIPs. It checks endpoint reachability
using ICMP during startup. Its configuration reader supports a subset of
wg-quick and does not run arbitrary wg-quick hooks. More complex peer and routing
configurations belong in the native host interface mode.

## Credentials and state

Select exactly one `configFile` runtime path or `sopsSecret` key per enabled
tunnel. Both keep plaintext private keys out of evaluation and derivations.
File paths must be absolute, normalized, outside `/nix/store`, and contain only
letters, digits, `/`, `_`, `-` and `.` for the upstream command interfaces.
Runtime files should be readable only by root. A named SOPS key is declared
automatically with mode `0400`; enable Nixstead's SOPS configuration as usual.
SOPS rotation restarts the associated tunnel and attached namespace services.
For files managed outside SOPS, restart the corresponding unit after replacement.

Tunnels have no application database or mutable library state to back up.
Preserve the encrypted SOPS file and its recovery identity separately. There is
no aggregate application health endpoint; inspect each tunnel's systemd unit
and `wg` handshake status. A running unit alone does not prove peer connectivity.

## ARR integration and coverage

The qBittorrent adapter can create its usual `nixqvpn` namespace or select one
of these shared namespaces. See [qBittorrent VPN](qbittorrent-vpn.md).

`service-wireguard-runtime` starts a real host tunnel and an independent
non-ARR service in a namespace, then checks routes and service DNS against a
local peer. Commercial provider compatibility and a general VPN server
deployment are outside this fixture.

## State and recovery boundary

Host interfaces and namespaces are reconstructed from declarative attachments
and runtime tunnel configuration, with secret material recovered from its SOPS
source. No archive of live interface state is required. Preserve encrypted source
and recipient identities; rotate the key by replacing that source and restarting
the affected tunnel rather than copying plaintext into Nix evaluation.

The maintained local-peer fixture creates disposable keys inside the guests,
installs the encrypted runtime source, starts one host tunnel and one attached
namespace service, and checks that both routes and namespace DNS reach the peer.
Configuration assertions cover source selection and invalid declarations.

All 16 dedicated configuration assertions passed on both supported architectures.
The bounded `x86_64-linux` startup check passed in 32.04 seconds. Key rotation, tunnel
loss, restart/reboot, loss of the encrypted source or age identity, commercial
providers, general server forwarding/NAT, automatic boot start and ARM execution
remain outside the maintained fast smoke.
