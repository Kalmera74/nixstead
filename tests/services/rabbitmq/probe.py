"""Generate disposable encrypted bootstrap credentials inside the guest."""

import json
import secrets
import sys


def password():
    return secrets.token_hex(24) + " quote' and$dollar"


assert sys.argv[1] == "generate"
print(
    json.dumps(
        {
            "devdb": {
                "rabbitmq": {"rootUser": "fixture-admin", "rootPassword": password()}
            },
            "fixture": {"clientPassword": password()},
        }
    )
)
