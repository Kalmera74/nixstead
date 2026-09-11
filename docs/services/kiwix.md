# Kiwix

Kiwix serves offline `.zim` archives such as Wikipedia snapshots. Nixstead
builds a Kiwix library index from the configured directory before starting
`kiwix-serve.service`.

## Enable and configure

```nix
nixstead.services.media.kiwix = {
  enable = true;
  domain = "wiki.home.arpa";
  port = 9090;
  paths.dataDir = "/var/lib/kiwix";
};
```

Place `.zim` files directly in `paths.dataDir`, then start
`kiwix-library-refresh.service`. The running server monitors the generated
`library.xml` and reloads additions and removals. Refresh builds a replacement
index first, so an invalid archive refuses the refresh without overwriting the
last usable index. An empty directory produces an empty catalogue. The generated
index is recreated at boot and does not need backup.

Nixstead treats source ZIM files as externally owned content. Back up unique
archives through the storage system that owns `paths.dataDir`; the Kiwix service
backup policy does not archive them.

The x86 VM check intentionally stays small: it verifies that the native service
generates and serves a valid empty catalogue on the configured loopback
listener. Archive browsing and search behavior are outside this wiring smoke.

## Credentials

The configured Kiwix endpoint has no application login. Access control must be
provided by the surrounding network or a separate authentication proxy.

Use `journalctl -u kiwix-library-refresh -u kiwix-serve` for diagnostics.
