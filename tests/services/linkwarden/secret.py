import json
import secrets
import sys

if sys.argv[1] != "generate":
    raise ValueError("expected generate")

print(
    json.dumps(
        {
            "linkwarden": {
                key: secrets.token_hex(32)
                for key in ["nextAuthSecret", "postgresPassword", "meiliMasterKey"]
            }
        }
    )
)
