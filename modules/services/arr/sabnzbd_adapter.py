"""SABnzbd category and ARR client relationships through supported APIs."""

from pathlib import Path
import hashlib
from urllib.parse import urlsplit


def call(api, mode, error_type, **parameters):
    result = api.request(
        "POST",
        "/api",
        {"mode": mode, "output": "json", "apikey": api.key, **parameters},
        form=True,
    )
    if isinstance(result, dict) and (
        result.get("status") is False or "error" in result
    ):
        raise error_type("SABnzbd rejected an authenticated API request")
    return result


def ensure(journal, sab, application, desired, update_fields, fields, error_type):
    def request(mode, **parameters):
        return call(sab, mode, error_type, **parameters)

    misc = request("get_config", section="misc")["config"]["misc"]
    for setting, path in (
        ("complete_dir", desired["complete"]),
        ("download_dir", desired["incomplete"]),
    ):
        if Path(misc[setting]) != Path(path):
            raise error_type(
                "Effective SABnzbd storage conflicts with the selected integration paths"
            )
    name = f"nixstead-usenet-{journal.category_label}-{journal.state['owner']}"
    category_key = "sabnzbd-" + journal.category_key
    categories = request("get_config", section="categories")["config"].get(
        "categories", []
    )
    current = journal.owned(
        category_key, name, [item for item in categories if item["name"] == name]
    )
    if current is None or current["dir"] != desired["categoryPath"]:
        if current is not None and request("queue")["queue"]["slots"]:
            raise error_type(
                "SABnzbd category path change requires an empty download queue"
            )
        journal.report("create" if current is None else "update", category_key, ["dir"])
        if not journal.config["dryRun"]:
            journal.intent(category_key, name)
            request(
                "set_config",
                section="categories",
                name=name,
                dir=desired["categoryPath"],
            )
            journal.finish(category_key)
    elif journal.state["resources"][category_key].get("pending"):
        journal.finish(category_key)
    journal.root_folder()
    client_key = journal.application + "-sabnzbd-client"
    client_name = "Nixstead SABnzbd " + journal.state["owner"]
    record = journal.state["resources"].get(client_key, {})
    clients = application.request("GET", journal.api_prefix + "/downloadclient")
    current = journal.owned(
        client_key,
        client_name,
        [
            item
            for item in clients
            if item["name"] == client_name
            or (record.get("id") is not None and item["id"] == record["id"])
        ],
    )
    endpoint = urlsplit(sab.endpoint)
    owned = {
        "host": endpoint.hostname,
        "port": endpoint.port,
        "useSsl": endpoint.scheme == "https",
        "urlBase": endpoint.path.rstrip("/"),
        "apiKey": sab.key,
        journal.category_field: name,
    }
    digest = hashlib.sha256((journal.state["owner"] + sab.key).encode()).hexdigest()
    if (
        current is not None
        and fields(current).get("apiKey") == "********"
        and record.get("credentialDigest") == digest
    ):
        try:
            application.request(
                "POST", journal.api_prefix + "/downloadclient/test", current
            )
        except error_type:
            pass
        else:
            owned["apiKey"] = "********"
    if current is None:
        schemas = [
            item
            for item in application.request(
                "GET", journal.api_prefix + "/downloadclient/schema"
            )
            if item["implementation"] == "Sabnzbd"
        ]
        if len(schemas) != 1:
            raise error_type("Missing or ambiguous ARR SABnzbd schema")
        resource = update_fields(schemas[0], owned)
    else:
        if current["implementation"] != "Sabnzbd":
            raise error_type("Owned SABnzbd client has an unexpected implementation")
        resource = update_fields(current, owned)
    resource.update(name=client_name, enable=True)
    if current == resource:
        if record.get("pending"):
            journal.finish(client_key, current["id"])
        return
    journal.report(
        "create" if current is None else "update",
        client_key,
        [
            name
            for name, value in owned.items()
            if current is None or fields(current).get(name) != value
        ]
        + ["enable"],
    )
    if journal.config["dryRun"]:
        return
    application.request("POST", journal.api_prefix + "/downloadclient/test", resource)
    if current is None:
        journal.intent(client_key, client_name, credentialDigest=digest)
        result = application.request(
            "POST", journal.api_prefix + "/downloadclient", resource
        )
    else:
        result = application.request(
            "PUT", journal.api_prefix + f"/downloadclient/{current['id']}", resource
        )
    journal.state["resources"][client_key]["credentialDigest"] = digest
    journal.finish(client_key, result["id"])
