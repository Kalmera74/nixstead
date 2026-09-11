# Jellyfin

Jellyfin streams local video, music, and photo libraries. Nixstead runs the
native `jellyfin.service`, configures its HTTP listener, enables graphics
support, and adds Jellyfin to the `video`, `render`, and shared media groups for
hardware transcoding and library access.

## Enable and configure

```nix
nixstead.services.media.jellyfin = {
  enable = true;
  domain = "watch.home.arpa";
  port = 8096;
};
```

Open `https://watch.home.arpa` and complete Jellyfin's setup wizard. Add media
libraries using host paths readable by the media group. Hardware transcoding is
selected in **Dashboard > Playback > Transcoding** after the corresponding GPU
device is available to the service.

## Initial credentials

The setup wizard creates the first administrator; Nixstead does not store that
password. For Homepage, create an API key under
**Dashboard > Advanced > API Keys** and run the Homepage integration helper.

Inspect it with `systemctl status jellyfin` and `journalctl -u jellyfin`.

## Recovery boundary

The service backup stops Jellyfin and archives its native `services.jellyfin.dataDir`,
including the application database, user identities, library records and watched
state. A separately configured `services.jellyfin.configDir` receives its own
archive slot; a config directory beneath the data directory is already included.
Restore reapplies the configured service owner/group. The default `/var/cache/jellyfin` cache is disposable and systemd recreates its
owned directory at each service start. Custom native cache paths keep their
native tmpfiles provisioning and need an available, correctly owned directory
when restoring without rebooting.
Missing `data/jellyfin.db` or a required directory slot causes restore to refuse
before stopping the live service or changing files.

Source video, audio and photo directories have separate ownership. They are not
part of this application-state backup. Back them up separately and make the same
library paths available before restarting the restored server. Preserving a
library record alone does not recover its source bytes.

The maintained smoke checks native HTTP readiness and writes an independent
file marker in each custom application/configuration root. Recovery erases those
roots and the disposable cache, restores the encrypted Borg archive once, then
checks readiness and both markers. Source-media libraries, user/library/playstate
workflows, GPU transcoding, repeated reboots and detailed failure cases are
outside this smoke.

The smoke makes no private-streaming authorization claim.

The maintained x86_64 clean-restore smoke passed in **81.77 seconds** with
native Jellyfin readiness and both independent root markers restored.

Configuration checks, including the cache lifecycle and custom native config
paths, pass on x86_64 and aarch64. ARM application runtime remains unverified.
