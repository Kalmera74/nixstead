"""Seerr relationships after administrator bootstrap, with explicit policy choices."""

from copy import deepcopy
from urllib.parse import quote, urlsplit


def connection_fields(endpoint, key):
    address = urlsplit(endpoint)
    return {
        "hostname": address.hostname,
        "port": address.port,
        "useSsl": address.scheme == "https",
        "baseUrl": address.path.rstrip("/"),
        "apiKey": key,
    }


def ensure_existing(journal, seerr, destination, key, error_type):
    application = destination["application"]
    resource_key = "seerr-existing-" + application
    selector = destination["existingServer"]
    route = "/api/v1/settings/" + application
    records = seerr.request("GET", route)
    record = journal.state["resources"].get(resource_key)
    if record is not None:
        if record.get("selector") != selector:
            raise error_type(
                "Existing Seerr server selector differs from its ownership journal"
            )
        matches = [item for item in records if item["id"] == record["id"]]
    else:
        matches = [
            item
            for item in records
            if (selector.get("id") is None or item["id"] == selector["id"])
            and (selector.get("name") is None or item["name"] == selector["name"])
        ]
    if len(matches) != 1:
        raise error_type(
            f"Expected exactly one existing Seerr {application} server; select its ID or name explicitly"
        )
    current = matches[0]
    owned = connection_fields(destination["endpoint"], key)
    # This API test is required on every run, including when no fields drifted.
    available = seerr.request("POST", route + "/test", owned)
    if current.get("activeProfileId") not in [
        profile["id"] for profile in available["profiles"]
    ] or current.get("activeDirectory") not in [
        folder["path"] for folder in available["rootFolders"]
    ]:
        raise error_type(
            "Existing Seerr profile or root folder is unavailable on the configured ARR service"
        )
    changed = [field for field, value in owned.items() if current.get(field) != value]
    if changed:
        journal.report("update", resource_key, changed)
    elif record is None:
        journal.report("manage", resource_key, list(owned))
    if journal.config["dryRun"]:
        return
    # Bind the explicit selection before writing, so partial failure cannot
    # reselect another user object. These five fields are the ownership scope.
    if record is None or changed:
        journal.intent(
            resource_key,
            current["name"],
            id=current["id"],
            selector=selector,
            fields=sorted(owned),
        )
    if changed:
        latest = seerr.request("GET", route)
        matches = [item for item in latest if item["id"] == current["id"]]
        if len(matches) != 1 or matches[0] != current:
            raise error_type(
                "Seerr server changed during reconciliation; retrying on the next run"
            )
        payload = deepcopy(current)
        payload.update(owned)
        payload.pop("id", None)
        seerr.request("PUT", route + "/" + str(current["id"]), payload)
        saved = [
            item for item in seerr.request("GET", route) if item["id"] == current["id"]
        ]
        if len(saved) != 1 or any(
            saved[0].get(field) != value for field, value in owned.items()
        ):
            raise error_type("Seerr did not retain the configured connection fields")
        seerr.request(
            "POST", route + "/test", {field: saved[0][field] for field in owned}
        )
    journal.finish(resource_key, current["id"])


def library_map(libraries, error_type):
    """Validate snapshots before any mutating API call; errors never contain keys."""
    if not isinstance(libraries, list):
        raise error_type("Invalid Jellyfin library list")
    result = {}
    for item in libraries:
        if (
            not isinstance(item, dict)
            or not isinstance(item.get("id"), str)
            or not item["id"]
            or any(character in item["id"] for character in ",\r\n")
            or not isinstance(item.get("name"), str)
            or item.get("type") not in ("movie", "show")
            or not isinstance(item.get("enabled"), bool)
            or item["id"] in result
        ):
            raise error_type("Invalid or ambiguous Jellyfin library data")
        result[item["id"]] = item
    return result


def discover_libraries(jellyfin, error_type):
    # Seerr's library GET mutates settings. Discover directly through Jellyfin's
    # read-only API instead, including on dry runs and when Seerr's cache exists.
    response = jellyfin.request("GET", "/Library/MediaFolders")
    if not isinstance(response, dict) or not isinstance(response.get("Items"), list):
        raise error_type("Invalid Jellyfin library discovery response")
    discovered = []
    movie_tv = []
    # Match the pinned Seerr mapLibraries adapter. Mixed/unknown collections can
    # remain selected by users, but only movies and tvshows match our policy.
    excluded = ("music", "books", "musicvideos", "homevideos", "boxsets")
    for item in response["Items"]:
        if not isinstance(item, dict) or (
            item.get("CollectionType") is not None
            and not isinstance(item["CollectionType"], str)
        ):
            raise error_type("Invalid Jellyfin library discovery response")
        if (
            item.get("Type") != "CollectionFolder"
            or item.get("CollectionType") in excluded
        ):
            continue
        discovered.append(
            {
                "id": item.get("Id"),
                "name": item.get("Name"),
                "type": "movie" if item.get("CollectionType") == "movies" else "show",
                "enabled": False,
            }
        )
        if item.get("CollectionType") in ("movies", "tvshows"):
            movie_tv.append(item.get("Id"))
    libraries = library_map(discovered, error_type)
    if not libraries:
        raise error_type(
            "No supported Jellyfin libraries discovered; create libraries in Jellyfin and retry"
        )
    return libraries, set(movie_tv)


def ensure_jellyfin(journal, seerr, connection, key, jellyfin, error_type):
    if jellyfin is None:
        raise error_type("Jellyfin discovery client is required")
    route = "/api/v1/settings/jellyfin"
    current = seerr.request("GET", route)
    libraries = library_map(current.get("libraries"), error_type)
    available, movie_tv = discover_libraries(jellyfin, error_type)
    enabled = {identity for identity, item in libraries.items() if item["enabled"]}
    if not enabled <= available.keys():
        raise error_type(
            "An enabled Seerr library is missing from Jellyfin discovery; check the server and library access before changing selections"
        )
    policy = connection.get(
        "libraryPolicy", "explicit" if connection.get("libraries") else "auto"
    )
    selected = set(connection.get("libraries", []))
    if policy not in ("auto", "preserve", "movies-and-tv", "explicit") or (
        policy == "explicit"
    ) != bool(selected):
        raise error_type("Invalid Jellyfin library policy or explicit selection")
    if not selected <= available.keys():
        raise error_type("An explicitly selected Jellyfin library is unavailable")
    if policy == "movies-and-tv" or (policy == "auto" and not libraries):
        selected |= movie_tv
    enabled |= selected
    expected = {
        identity: dict(item, enabled=identity in enabled)
        for identity, item in available.items()
    }
    endpoint = urlsplit(connection["endpoint"])
    owned = {
        "ip": endpoint.hostname,
        "port": endpoint.port,
        "useSsl": endpoint.scheme == "https",
        "urlBase": endpoint.path.rstrip("/"),
        "apiKey": key,
    }
    changed = [field for field, value in owned.items() if current.get(field) != value]
    refresh = libraries != expected
    if changed:
        journal.report("update", "seerr-jellyfin", changed)
    if refresh:
        journal.report("update", "seerr-jellyfin-library", ["libraries", "enabled"])
    if journal.config["dryRun"] or not (changed or refresh):
        return

    def unchanged(snapshot):
        if seerr.request("GET", route) != snapshot:
            raise error_type(
                "Seerr Jellyfin settings changed during reconciliation; retrying on the next run"
            )

    unchanged(current)
    if changed:
        seerr.request("POST", route, owned)
        updated = seerr.request("GET", route)
        if any(updated.get(field) != value for field, value in owned.items()):
            raise error_type("Seerr did not retain the configured Jellyfin connection")
        if library_map(updated.get("libraries"), error_type) != libraries:
            raise error_type(
                "Seerr Jellyfin libraries changed during reconciliation; retrying on the next run"
            )
        current = updated
    if refresh:
        unchanged(current)
        # Refresh and selection are one saved operation. Seerr rejects enable=
        # but accepts omission as none selected. Omit only when the computed
        # selection is intentionally empty, never just because we are syncing.
        # After a lost reply auto preserves the saved list, including all-off.
        selection_query = (
            "&enable=" + quote(",".join(sorted(enabled)), safe="") if enabled else ""
        )
        result = seerr.request(
            "GET",
            route + "/library?sync=true" + selection_query,
        )
        if (
            library_map(result, error_type) != expected
            or library_map(seerr.request("GET", route).get("libraries"), error_type)
            != expected
        ):
            raise error_type(
                "Jellyfin discovery changed or Seerr did not retain library selections; inspect selections and retry"
            )


def ensure(journal, seerr, desired, keys, error_type, *, jellyfin=None):
    # Authentication alone must not turn a fresh setup wizard into an assumed
    # administrator account. This is a supported API, never a database query.
    users = seerr.request("GET", "/api/v1/user?take=1")
    if not any(user.get("id") == 1 for user in users.get("results", [])):
        raise error_type(
            "Seerr administrator bootstrap must be completed before integration"
        )
    if desired.get("jellyfin"):
        ensure_jellyfin(
            journal, seerr, desired["jellyfin"], keys["jellyfin"], jellyfin, error_type
        )
    for destination in desired["destinations"]:
        application = destination["application"]
        if destination.get("existingServer") is not None:
            ensure_existing(journal, seerr, destination, keys[application], error_type)
            continue
        resource_key = "seerr-" + application
        name = f"Nixstead {application.capitalize()} {journal.state['owner']}"
        route = "/api/v1/settings/" + application
        records = seerr.request("GET", route)
        record = journal.state["resources"].get(resource_key, {})
        current = journal.owned(
            resource_key,
            name,
            [
                item
                for item in records
                if item["name"] == name
                or (record.get("id") is not None and item["id"] == record["id"])
            ],
        )
        owned = connection_fields(destination["endpoint"], keys[application])
        # Seerr tests the real ARR endpoint and returns selectable profiles/roots.
        available = seerr.request("POST", route + "/test", owned)
        profiles = [
            profile
            for profile in available["profiles"]
            if profile["id"] == destination["qualityProfileId"]
        ]
        if len(profiles) != 1 or destination["rootFolder"] not in [
            root["path"] for root in available["rootFolders"]
        ]:
            raise error_type(
                "Explicit Seerr quality profile or root folder is unavailable"
            )
        if destination["isDefault"] and any(
            item["isDefault"]
            and item["is4k"] == destination["is4k"]
            and (current is None or item["id"] != current["id"])
            for item in records
        ):
            raise error_type(
                "A different Seerr default destination exists; refusing to alter user-owned configuration"
            )
        owned.update(
            name=name,
            activeProfileId=profiles[0]["id"],
            activeProfileName=profiles[0]["name"],
            activeDirectory=destination["rootFolder"],
            is4k=destination["is4k"],
            isDefault=destination["isDefault"],
            preventSearch=not destination["searchOnRequest"],
        )
        resource = (
            deepcopy(current)
            if current is not None
            else {
                "tags": [],
                "syncEnabled": False,
                "tagRequests": False,
                "overrideRule": [],
            }
        )
        if application == "sonarr" and current is None:
            resource.update(
                seriesType="standard",
                animeSeriesType="anime",
                enableSeasonFolders=True,
                monitorNewItems="all",
            )
        if application == "radarr" and current is None:
            resource["minimumAvailability"] = "released"
        resource.update(owned)
        if resource == current:
            if record.get("pending"):
                journal.finish(resource_key, current["id"])
            continue
        journal.report(
            "create" if current is None else "update",
            resource_key,
            [
                key
                for key, value in owned.items()
                if current is None or current.get(key) != value
            ],
        )
        if journal.config["dryRun"]:
            continue
        if current is None:
            journal.intent(resource_key, name)
            result = seerr.request("POST", route, resource)
        else:
            # Seerr marks id read-only and rejects it in a PUT body.
            resource.pop("id", None)
            result = seerr.request("PUT", route + "/" + str(current["id"]), resource)
        journal.finish(resource_key, result["id"])
