# Uptime Kuma

Uptime Kuma performs active uptime checks and publishes status pages. Nixstead
runs a digest-pinned Docker container with persistent state.

## Enable and configure

```nix
nixstead.services.dev.uptimekuma = {
  enable = true;
  domain = "uptimekuma.home.arpa";
  port = 3010;
  paths.dataDir = "/var/lib/uptimekuma";
};
```

`images.application` can override the pinned image. Add monitors, notifications,
and status pages in the UI. The Homepage widget expects a public status page
with slug `home` in the current registry metadata.

## Initial credentials

Open `https://uptimekuma.home.arpa`; the first-run page creates the
administrator. Nixstead does not store that password.

Inspect `docker-uptimekuma.service` and `docker logs uptimekuma`.

## Dedicated service smokes

The combined smoke starts the pinned container, checks its HTTP page and writes
a small volume marker. Recovery erases the volume, runs one shipped Borg restore,
and checks HTTP readiness and the original marker. Monitor transitions,
notifications, account workflows, failure and restart/reboot matrices are outside
this smoke.

The reduced clean-restore smoke passed on x86_64-linux with KVM in 324.43
seconds on 2026-09-09, including the pinned image load and native startup.

A single `service-uptimekuma-recovery` VM covers initial startup/readiness and
one clean backup/restore.
