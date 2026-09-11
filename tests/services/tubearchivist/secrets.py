"""Generate disposable encrypted VM credentials at guest activation."""

import json
import secrets

keys = ["username", "password", "elasticPassword"]
print(json.dumps({"tubearchivist": {key: secrets.token_hex(24) for key in keys}}))
