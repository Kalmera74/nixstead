# qBittorrent VPN confinement

Confinement is optional and uses the [shared WireGuard module](wireguard.md),
which owns the pinned VPN-Confinement backend, credentials and namespace rules.
The ARR adapter only selects a namespace and configures qBittorrent access.
Only the selected qBittorrent service enters the namespace. Other ARR services
continue to use their ordinary host network context.

```nix
nixstead.services.arr.qbittorrent = {
  enable = true;
  vpn.enable = true;
};
```

Encrypt the complete provider wg-quick configuration as
`qbittorrent/wireguard` in the host's SOPS file. It must specify the address,
DNS server, peer endpoint and full-tunnel IPv4/IPv6 AllowedIPs. The schema-only
example is not a working VPN configuration. An explicit
`vpn.wireguardConfigFile` runtime path takes precedence. Never put the private
key or plaintext configuration in a Nix expression or store path.

To use an explicitly configured shared tunnel instead, select its namespace:

```nix
nixstead.services.wireguard = {
  enable = true;
  namespaces.apps.sopsSecret = "wireguard/apps";
};
nixstead.services.arr.qbittorrent = {
  enable = true;
  vpn = {
    enable = true;
    namespace = "apps";
  };
};
```

In this mode, configure the credential source on the shared namespace and leave
`vpn.wireguardConfigFile` unset. qBittorrent is attached automatically; other
services can use the namespace's `services` list. Disabling the selected
namespace while qBittorrent VPN remains enabled is rejected during evaluation.

The private namespace `nixqvpn` uses `192.168.241.0/24` and
`fd93:9701:241::/64` for host communication. These ranges must not overlap local
networks. qBittorrent's WebUI listens on its namespace address. An authenticated
host-loopback socket proxy lets ARR, Nginx and health checks use the registry's
usual internal endpoint. The namespace accepts this port only from its host
bridge address; the wrapper does not expose a general host DNAT port.
The shared module exposes these addresses as overrideable settings, and ARR
uses their effective values for both the WebUI listener and proxy target.

Keep qBittorrent's exposure set to `loopback`. Select Nginx exposure separately.
No localhost authentication bypass or public torrent port is enabled. Incoming
provider port forwarding is outside this implementation. Custom containers
cannot assume their own localhost reaches the host proxy.

SOPS key changes restart the namespace and its dependent downloader. Tunnel loss
blocks IPv4/IPv6 egress and DNS until reconnection; stopping the namespace stops
qBittorrent. Inspect `nixqvpn.service`, `qbittorrent.service` and
`nixstead-qbittorrent-proxy.socket`. The
[VPN VM check](../support-matrix.md) exercises these transitions with a local
WireGuard peer and DNS fixture. It does not certify a particular commercial
provider configuration. Enable confinement only after supplying a provider
configuration.
