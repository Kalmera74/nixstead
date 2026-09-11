"""Own only the explicitly selected Bazarr connection fields."""

from urllib.parse import urlsplit


def ensure_connections(journal, api, applications, api_keys, error_type):
    current = api.request("GET", "/api/system/settings")
    changes = {}
    for desired in applications:
        application = desired["application"]
        endpoint = urlsplit(desired["endpoint"])
        owned = {
            "general": {"use_" + application: True},
            application: {
                "ip": endpoint.hostname,
                "port": endpoint.port or (443 if endpoint.scheme == "https" else 80),
                "ssl": endpoint.scheme == "https",
                "base_url": endpoint.path.rstrip("/") or "/",
                "apikey": api_keys[application],
            },
        }
        fields = []
        for section, values in owned.items():
            for name, value in values.items():
                if name not in current.get(section, {}):
                    raise error_type(
                        "Bazarr settings schema lacks a required connection field"
                    )
                effective = current[section][name]
                if name == "base_url":
                    effective, value = (effective or "").rstrip("/"), value.rstrip("/")
                if effective != value:
                    changes[f"settings-{section}-{name}"] = (
                        str(value).lower() if isinstance(value, bool) else value
                    )
                    fields.append(section + "." + name)
        if fields:
            journal.report("update", "bazarr-" + application, fields)
    if changes and not journal.config["dryRun"]:
        # Bazarr accepts partial settings through form POST. Sending its entire
        # settings response could overwrite providers, languages or credentials.
        api.request("POST", "/api/system/settings", changes, form=True)
