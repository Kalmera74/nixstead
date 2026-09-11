"""Runtime-encrypted credentials for the native startup smoke."""

import json
import secrets
import sys


if sys.argv[1] == "generate":
    print(json.dumps({"fixture": {"paperlessPassword": secrets.token_hex(32)}}))
else:
    raise ValueError("expected generate")
