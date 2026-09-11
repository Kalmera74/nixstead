"""Generate disposable encrypted bootstrap credentials inside the guest."""

import json
import secrets
import sys

assert sys.argv[1] == "generate"
print(json.dumps({"vaultwarden": {"adminToken": secrets.token_hex(32)}}))
