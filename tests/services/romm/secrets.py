"""Generate disposable encrypted VM credentials at guest activation."""

import json
import secrets

keys = [
    "authSecretKey",
    "dbPassword",
    "dbRootPassword",
    "igdbClientId",
    "igdbClientSecret",
    "mobyGamesApiKey",
    "screenscraperUser",
    "screenscraperPassword",
    "steamGridDbApiKey",
    "retroAchievementsApiKey",
]
values = {key: "" for key in keys}
for key in ("authSecretKey", "dbPassword", "dbRootPassword"):
    values[key] = secrets.token_hex(24)
print(json.dumps({"romm": values}))
