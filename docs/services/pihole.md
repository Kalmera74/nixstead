# Pi-hole integration

The Pi-hole entry represents an existing external Pi-hole; Nixstead does not
install Pi-hole. It can generate an HTTPS reverse proxy, Homepage card/widget,
DNS participation, and an external health check using the configured target.

## Configure

```nix
nixstead.services.pihole = {
  enable = true;
  ip = "192.168.1.2";
  domain = "pihole.home.arpa";
  port = 80;
};
```

The target must already serve Pi-hole on that IP and port. The generated browser
link points to `/admin/`.

## Opt-in local DNS synchronization

`nixstead.services.pihole.dnsSync.enable` defaults to `false`. Set it to `true`
explicitly to authorize DNS writes. When a runtime Pi-hole credential is
available, Nixstead then installs a oneshot service that reconciles
every enabled registry entry with `dns = true` on boot and whenever a deployed
service is enabled or disabled. All desired records point to
`nixstead.host.network.lan`, where Nginx serves the registry-generated virtual hosts.

The sync service reuses the encrypted `homepage/piholeApiKey` application
password when the Homepage Pi-hole widget exposes that secret. For a host that
does not use Homepage, provide another root-readable runtime file:

```nix
nixstead.services.pihole.dnsSync = {
  enable = true;
  credentialFile = "/run/secrets/pihole-application-password";
};
```

An empty or `replace-me` credential leaves Pi-hole unchanged. The service
stores the exact domains it has managed under
`/var/lib/nixstead-pihole-dns-sync`; disabling a service therefore removes
only a record previously claimed by Nixstead, not unrelated manual records in
the same DNS zone. Set `nixstead.services.pihole.dnsSync.enable = false` to keep DNS
fully manual.

Existing deployments that relied on automatic reconciliation must add the
explicit toggle. Enabling the remote Pi-hole card/proxy or configuring its
widget credential alone leaves DNS unchanged.

## Credentials

Pi-hole's administrator password remains on the Pi-hole host. For Homepage,
create a Pi-hole 6 application password and run
`nixstead --host <host> credentials configure homepage`; it stores
the value as `homepage/piholeApiKey`. Diagnose reachability from the Nixstead
host before troubleshooting Nginx.

## State and recovery boundary

This suite owns the remote endpoint, proxy/widget wiring and local DNS-sync
ownership journal. Appliance configuration, query databases and DNS-server
recovery belong to the Pi-hole administrator. The local journal records which
records Nixstead owns; restoring or reconstructing the adapter must not authorize
pruning unrelated records.

Configuration tests prove the default leaves DNS-sync absent even when a widget
credential exists, and separately select its enabled profile. The disposable
runtime test uses the shipped oneshot against a narrow Pi-hole v6 API peer. It
authenticates with a runtime SOPS credential, applies the configured records
once and exits successfully. Idempotence, credential rotation, dependency
failures, reboot, live Pi-hole compatibility, DNS queries and appliance recovery
remain outside this fast smoke.
