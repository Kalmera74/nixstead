# Nginx reverse proxy

This directory owns local TLS and registry-generated virtual hosts.

- `nginx.nix` enables Nginx, manages the local or external CA, publishes the
  public CA certificate to the host user's home, and renews service
  certificates with a daily timer.
- `lib.nix` contains reusable TLS virtual-host helpers.
- `registry-proxies.nix` renders proxies for enabled registry services.

```nix
nixstead.services.nginx.enable = true;
nixstead.services.media.jellyfin.domain = "watch.home.arpa";
```

An existing CA can be selected with runtime paths that do not copy its private
key into the Nix store:

```nix
nixstead.services.nginx.ca = {
  certificateFile = "/etc/nixstead-ca/root-ca.crt";
  privateKeyFile = "/run/secrets/nixstead-ca-key";
};
```

Local services proxy to loopback; external integrations proxy to their resolved
IP. Add standard proxy behavior to the service registry instead of creating one
file per service. See [Networking](../../../docs/networking.md).
