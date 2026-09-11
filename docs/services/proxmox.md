# Proxmox integration

The Proxmox entry integrates an existing external Proxmox VE host; Nixstead
does not install or administer the hypervisor. It generates an HTTPS proxy,
WebSocket support, a Homepage widget, and an external health check.

## Configure

```nix
nixstead.services.proxmox = {
  enable = true;
  ip = "192.168.1.3";
  domain = "proxmox.home.arpa";
  port = 8006;
};
```

The proxy currently permits Proxmox's self-signed upstream certificate while
serving the Nixstead-managed certificate to clients.

## Credentials

Create a dedicated Proxmox user and privilege-separated API token, grant both
the read-only `PVEAuditor` role at `/`, and run the Homepage integration helper.
It stores `user@realm!token-id` and the one-time token secret under the encrypted
Homepage branch. These credentials are for the widget, not browser login.

## State and recovery boundary

The adapter reconstructs its endpoint, TLS proxy and widget/token destinations
from configuration and encrypted source. No local Proxmox server, external
virtual machine backup or hypervisor recovery is implied. Keep API token material
out of ordinary environment values and preserve encrypted recipient identities.

The disposable runtime test exercises the generated Homepage widget against a
self-signed HTTPS peer implementing Proxmox's cluster-resources endpoint. It
starts Homepage and the peer, then verifies one authenticated resource response.
Credential rotation, dependency failures, restart/reboot and live-version
compatibility remain outside this fast smoke. External hypervisor upgrades,
guest backup and recovery belong to its administrator.
