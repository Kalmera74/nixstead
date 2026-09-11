# Nginx

Nginx is the registry-driven reverse proxy and local TLS terminator. When
`nixstead.services.nginx.enable` is true, each enabled proxied child gets a vhost
from resolved registry metadata, keeping domain, target and WebSocket behavior
aligned. Disabling this proxy also removes its managed TLS vhosts and certificate
requirements. An application such as Nextcloud can still use its own native
nginx HTTP listener.

## Enable and configure

```nix
nixstead.services.nginx = {
  enable = true;
  ca = {
    commonName = "homelab-local-ca";
    validityDays = 3650;
    certificateValidityDays = 825;
    renewBeforeDays = 30;
  };
};
```

By default Nixstead generates a local CA and per-service certificates. To use
an external CA, set both `ca.certificateFile` and `ca.privateKeyFile`; the
private key must be a runtime path outside the Nix store. Certificates are
checked daily by `nginx-local-certificates.timer`.

## Credentials and operation

Nginx has no UI login. Install the published CA certificate on clients that
must trust `*.home.arpa`. Inspect `nginx-local-certificates.service`, run
`nginx -t` through the built system configuration, and check `nginx.service`.

## State and recovery boundary

The generated CA identity in `/var/lib/nginx/local-ca` is durable. Keep its
private key and certificate together in an access-controlled independent backup,
or provide the same external certificate/key from encrypted runtime sources.
Declarative vhosts and issued leaf certificates can be regenerated; the same CA
identity cannot be recreated from their configuration.

The supported disaster fallback is deliberate retrust: retire the lost trust
anchor, generate a new CA and redistribute its public certificate to every
client. The certificate helper refuses to silently replace a missing/invalid
private key when a CA certificate remains. Do not delete that certificate as an
automatic recovery step.

The maintained `service-nginx-runtime` smoke starts native nginx and a real local
Prometheus backend. An independent client trusts the generated CA, reaches the
registry proxy over HTTPS and cannot reach the loopback backend directly. Local
CA archive recovery, rotation/retrust, repeated lifecycle, upstream failures,
WebSockets, external certificate authorities, ARM runtime and upgrades remain
unverified.
