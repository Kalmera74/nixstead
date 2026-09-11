"""Prowlarr application registrations; indexers remain user-owned."""

import hashlib
from copy import deepcopy


def ensure_profiles(journal, api, desired_profiles):
    for label, desired in desired_profiles.items():
        key = "prowlarr-profile-" + label
        name = f"Nixstead {label} {journal.state['owner']}"
        record = journal.state["resources"].get(key, {})
        current = journal.owned(
            key,
            name,
            [
                item
                for item in api.request("GET", "/api/v1/appprofile")
                if item["name"] == name
                or (record.get("id") is not None and item["id"] == record["id"])
            ],
        )
        resource = deepcopy(current) if current is not None else {}
        resource.update(name=name, **desired)
        if resource == current:
            if record.get("pending"):
                journal.finish(key, current["id"])
            continue
        journal.report(
            "create" if current is None else "update",
            key,
            [
                field
                for field in desired
                if current is None or current.get(field) != desired[field]
            ],
        )
        if journal.config["dryRun"]:
            continue
        if current is None:
            journal.intent(key, name)
            result = api.request("POST", "/api/v1/appprofile", resource)
        else:
            result = api.request("PUT", f"/api/v1/appprofile/{current['id']}", resource)
        journal.finish(key, result["id"])


def ensure_applications(
    journal, api, applications, api_keys, update_fields, fields, error_type
):
    for desired in applications:
        application = desired["application"]
        key = "prowlarr-" + application
        name = f"Nixstead {application.capitalize()} {journal.state['owner']}"
        records = api.request("GET", "/api/v1/applications")
        record = journal.state["resources"].get(key, {})
        matches = [
            item
            for item in records
            if item["name"] == name
            or (record.get("id") is not None and item["id"] == record["id"])
        ]
        current = journal.owned(key, name, matches)
        owned_fields = {
            "baseUrl": desired["endpoint"],
            "prowlarrUrl": api.endpoint,
            "apiKey": api_keys[application],
        }
        if desired["categories"] is not None:
            owned_fields["syncCategories"] = desired["categories"]
        if application == "sonarr" and desired["animeCategories"] is not None:
            owned_fields["animeSyncCategories"] = desired["animeCategories"]
        credential_digest = hashlib.sha256(
            (journal.state["owner"] + api_keys[application]).encode()
        ).hexdigest()
        if (
            current is not None
            and fields(current).get("apiKey") == "********"
            and record.get("credentialDigest") == credential_digest
        ):
            try:
                api.request("POST", "/api/v1/applications/test", current)
            except error_type:
                pass
            else:
                owned_fields["apiKey"] = "********"
        if current is None:
            schemas = [
                item
                for item in api.request("GET", "/api/v1/applications/schema")
                if item["implementation"] == application.capitalize()
            ]
            if len(schemas) != 1:
                raise error_type("Missing or ambiguous Prowlarr application schema")
            resource = update_fields(schemas[0], owned_fields)
        else:
            if current["implementation"] != application.capitalize():
                raise error_type(
                    "Owned Prowlarr registration has an unexpected implementation"
                )
            resource = update_fields(current, owned_fields)
        resource.update(name=name, syncLevel=desired["syncLevel"])
        if desired["tags"] is not None:
            available_tags = {tag["id"] for tag in api.request("GET", "/api/v1/tag")}
            if not set(desired["tags"]) <= available_tags:
                raise error_type("Selected Prowlarr tags do not exist")
            resource["tags"] = desired["tags"]
        if resource == current:
            if record.get("pending"):
                journal.finish(key, current["id"])
            continue
        changed = [
            field
            for field in owned_fields
            if current is None or fields(current).get(field) != owned_fields[field]
        ]
        changed += [
            field
            for field in ("name", "syncLevel", "tags")
            if field in resource
            and (current is None or resource[field] != current.get(field))
        ]
        journal.report("create" if current is None else "update", key, changed)
        if journal.config["dryRun"]:
            continue
        api.request("POST", "/api/v1/applications/test", resource)
        if current is None:
            journal.intent(key, name, credentialDigest=credential_digest)
            result = api.request("POST", "/api/v1/applications", resource)
        else:
            result = api.request(
                "PUT", f"/api/v1/applications/{current['id']}", resource
            )
        journal.state["resources"][key]["credentialDigest"] = credential_digest
        journal.finish(key, result["id"])
