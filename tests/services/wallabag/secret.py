import json
import secrets
import sys


if sys.argv[1] != "generate":
    raise ValueError("expected generate")

print(json.dumps({"wallabag": {"databasePassword": secrets.token_urlsafe(24)}}))
