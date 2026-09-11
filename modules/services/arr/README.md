# ARR stack

This directory defines the ARR download-automation stack:

- Sonarr, Radarr, Lidarr, Readarr, Bazarr, and Prowlarr;
- qBittorrent, SABnzbd, and Shelfmark; and
- Swaparr.

`arr.nix` defines the parent and child options and imports each implementation.
Registry metadata supplies standard domains, ports, proxy cards, health checks,
secrets, backups, firewall exposure, and preset membership.

```nix
nixstead.services.arr = {
  enable = true;
  lidarr.enable = false;
  readarr.enable = false;
  swaparr.enable = false;
};
```

Integration behavior must key off each child toggle. See
[Services](../../../docs/services.md) and the
[per-service guides](../../../docs/services/README.md).

The dedicated service checks share one combined startup and recovery VM.
They check native listeners, private runtime credentials, one selected
qBittorrent-to-Sonarr reconciliation, and dry-run Swaparr worker startup. The
recovery check erases the nine stateful application roots and the reconciliation
journal, then checks readiness and test-owned file markers after one shipped
Borg restore. Media acquisition, queues, imports, and library workflows are
outside this smoke fixture. Swaparr has startup coverage only; its workers keep
running during the stateful applications' restore.
