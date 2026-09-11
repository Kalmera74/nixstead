"""Selected native ARR ntfy notifications; send tests only when configuration changes."""

import hashlib


def ensure(journal, api, desired, token, update_fields, fields, error_type):
    key = journal.application + "-ntfy"
    name = "Nixstead ntfy " + journal.state["owner"]
    route = journal.api_prefix + "/notification"
    record = journal.state["resources"].get(key, {})
    current = journal.owned(
        key,
        name,
        [
            item
            for item in api.request("GET", route)
            if item["name"] == name
            or (record.get("id") is not None and item["id"] == record["id"])
        ],
    )
    owned = {
        "serverUrl": desired["endpoint"],
        "topics": desired["topics"],
        "accessToken": token,
    }
    digest = hashlib.sha256((journal.state["owner"] + token).encode()).hexdigest()
    if (
        current is not None
        and fields(current).get("accessToken") == "********"
        and record.get("credentialDigest") == digest
    ):
        # Testing an unchanged notification sends an actual message. Unlike a
        # download-client test, this cannot be used as a periodic health probe.
        owned["accessToken"] = "********"
    if current is None:
        schemas = [
            item
            for item in api.request("GET", route + "/schema")
            if item["implementation"] == "Ntfy"
        ]
        if len(schemas) != 1:
            raise error_type(
                "The pinned application lacks a unique native ntfy notification adapter"
            )
        resource = update_fields(schemas[0], owned)
    else:
        if current["implementation"] != "Ntfy":
            raise error_type("Owned notification has an unexpected implementation")
        resource = update_fields(current, owned)
    for event, enabled in desired["events"].items():
        if event not in resource:
            raise error_type(
                "The selected notification event is unsupported by this application"
            )
        resource[event] = enabled
    resource["name"] = name
    if resource == current:
        if record.get("pending"):
            journal.finish(key, current["id"])
        return
    changed = [
        field
        for field, value in owned.items()
        if current is None or fields(current).get(field) != value
    ]
    changed += [
        event
        for event in desired["events"]
        if current is None or resource[event] != current.get(event)
    ]
    journal.report("create" if current is None else "update", key, changed)
    if journal.config["dryRun"]:
        return
    api.request("POST", route + "/test", resource)
    if current is None:
        journal.intent(key, name, credentialDigest=digest)
        result = api.request("POST", route, resource)
    else:
        result = api.request("PUT", route + "/" + str(current["id"]), resource)
    journal.state["resources"][key]["credentialDigest"] = digest
    journal.finish(key, result["id"])
