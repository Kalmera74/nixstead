# Komga

Komga serves comics and manga from local libraries. Nixstead runs the native
`komga.service` and exposes its HTTP listener through Nginx.

## Enable and configure

```nix
nixstead.services.media.komga = {
  enable = true;
  domain = "komga.home.arpa";
  port = 25600;
};
```

Open `https://komga.home.arpa`, create the initial account, and add libraries
using paths readable by the Komga service. Library scanning, metadata, and user
permissions are managed in the application.

Komga's application database and settings under `/var/lib/komga` are included
in the service backup. Library source files are owned by their storage service
and need a separate backup policy.

The combined x86 VM check intentionally stays small: it verifies native startup
and HTTP readiness, then runs one encrypted backup and restore into empty
application storage. It does not exercise reader workflows or library scanning.

## Initial credentials

Nixstead does not preseed a Komga account. The first account is created during
onboarding. If Homepage uses the Komga widget, provide a dedicated Komga
username and password through the Homepage integration helper.

Inspect it with `systemctl status komga` and `journalctl -u komga`.
