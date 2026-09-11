"""Generate disposable ARR credentials directly into the guest SOPS input."""

import json
import secrets
import sys

assert sys.argv[1] == "generate"
values = {
    service: {"apiKey": secrets.token_hex(16)}
    for service in ("sonarr", "radarr", "lidarr", "prowlarr", "bazarr", "sabnzbd")
}
values["qbittorrent"] = {
    "username": "fixture",
    "password": secrets.token_hex(24),
}
values["swaparr"] = {"readarrApiKey": secrets.token_hex(16)}
print(json.dumps(values))
