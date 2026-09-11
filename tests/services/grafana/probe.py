"""Generate disposable encrypted bootstrap credentials inside the guest."""

import json
import secrets
import sys

assert sys.argv[1] == "generate"
print(
    json.dumps(
        {
            "devdb": {
                "grafana": {
                    "adminUser": "fixture-admin",
                    "adminPassword": secrets.token_hex(20) + "'quoted$fixture",
                    "secretKey": secrets.token_hex(32),
                }
            },
            "fixture": {
                "datasourcePassword": secrets.token_hex(24) + "'datasource$fixture"
            },
        }
    )
)
