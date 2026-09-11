# Tailscale

Tailscale provides mesh-VPN access. Nixstead enables `tailscaled.service` and
optionally configures client/server routing features and advertised routes.

## Enable and configure

```nix
nixstead.services.tailscale = {
  enable = true;
  useRoutingFeatures = "server";
  advertiseRoutes = ["192.168.1.0/24"];
};
```

`useRoutingFeatures` accepts `none`, `client`, `server`, or `both`. Advertised
routes still require approval in the Tailscale administration console and
appropriate forwarding/firewall policy.

## Initial credentials

Nixstead does not store a Tailscale auth key. After first activation, run
`sudo tailscale up` and follow its login URL, or provision the node using your
own approved out-of-band method. Inspect `tailscaled.service` and `tailscale
status`.

## State and recovery boundary

Nixstead's baseline loss-of-state contract is re-enrollment. Preserve encrypted
configuration and the declarative routing settings; after losing the daemon's
local identity, enroll a new node through the isolated or administrator-approved
control plane, approve its routes and retire the old node. The replacement may
receive a new identity/address. Applications must not infer address continuity.

There is no automatic archive of the daemon's device credentials. Restoring a
copied live device identity risks duplicate nodes and requires a separate secure
policy. A fixture must prove restart/reboot identity continuity plus expired or
rejected enrollment, control-plane outage and successful re-enrollment before
this recovery flow is considered verified.

## Dedicated checks

`service-tailscale-config` checks isolated daemon selection, routing and route
arguments, disabled behavior and the absence of implicit enrollment credentials
on x86-64 and AArch64. `service-tailscale-runtime` starts the native daemon and
checks its local socket and `NeedsLogin` status with no assigned Tailscale
addresses. It performs no control-plane enrollment or external connectivity
test. Enrolled identity continuity and re-enrollment recovery remain unverified.
