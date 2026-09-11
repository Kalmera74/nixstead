# TrueNAS integration

The TrueNAS entry integrates an existing external TrueNAS system. Nixstead
does not manage pools or shares; it generates a reverse proxy, Homepage
card/widget, DNS participation, and an external HTTP health check.

## Configure

```nix
nixstead.services.truenas = {
  enable = true;
  ip = "192.168.1.4";
  domain = "nas.home.arpa";
  port = 80;
};
```

Set the target scheme/port to match the upstream registry behavior before
activation. Storage administration remains entirely on TrueNAS.

## Credentials

Create a narrowly scoped TrueNAS API key for the Homepage widget and run
`nixstead --host <host> credentials configure homepage`. The helper
stores it as `homepage/truenasApiKey`; Nixstead does not copy the TrueNAS web
password. Test direct reachability to the TrueNAS target when the proxy returns
502.

## State and recovery boundary

The adapter owns endpoint, proxy and widget-key wiring; encrypted source owns
the runtime API credential. Pool import, appliance accounts, snapshots and file
recovery remain the TrueNAS administrator's responsibility. Enabling this remote
entry does not mount a share or install a local appliance.

CIFS/NFS consumers require their own tested storage contract and must not infer
recovery from a working dashboard card. The shared disposable Homepage/TrueNAS
runtime test starts both components and checks one authenticated system/alert
widget response with the runtime SOPS key. Credential rotation, dependency
failures, restart/reboot and live-appliance compatibility remain outside this
fast smoke.
