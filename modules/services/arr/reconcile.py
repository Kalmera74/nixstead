"""Ensure explicitly selected ARR relationships, without pruning application state."""

import argparse
from copy import deepcopy
import fcntl
import hashlib
import http.cookiejar
import json
import os
from pathlib import Path
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


class ReconcileError(Exception):
    """Messages must be safe to publish to systemd and the status command."""


def write_json(path, value):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".pending-")
    try:
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(value, stream, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        fd = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    finally:
        Path(temporary).unlink(missing_ok=True)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ReconcileError("Unexpected API redirect; use a direct internal endpoint")


class API:
    def __init__(self, endpoint, key=None, key_header="X-Api-Key"):
        url = urllib.parse.urlsplit(endpoint)
        if (
            url.scheme not in ("http", "https")
            or url.username
            or url.password
            or url.query
            or url.fragment
        ):
            raise ReconcileError("Invalid internal API endpoint")
        self.endpoint = endpoint.rstrip("/")
        self.key = key
        self.key_header = key_header
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            NoRedirect(),
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
        )

    def request(self, method, path, data=None, form=False, raw=False):
        headers = {"Accept": "application/json", "Referer": self.endpoint}
        if self.key:
            headers[self.key_header] = self.key
        body = None
        if data is not None:
            body = (
                urllib.parse.urlencode(data, doseq=True) if form else json.dumps(data)
            ).encode()
            headers["Content-Type"] = (
                "application/x-www-form-urlencoded" if form else "application/json"
            )
        request = urllib.request.Request(
            self.endpoint + path, data=body, headers=headers, method=method
        )
        try:
            with self.opener.open(request, timeout=10) as response:
                text = response.read(4 * 1024 * 1024).decode()
            return text if raw or not text else json.loads(text)
        except urllib.error.HTTPError as error:
            error.close()
            raise ReconcileError(
                (
                    "Application credential drift; explicit repair required"
                    if error.code in (401, 403)
                    else f"Application API returned HTTP {error.code}"
                )
            ) from None
        except (OSError, ValueError):
            raise ReconcileError(
                "Application API unavailable or returned invalid data"
            ) from None

    def ready(self, path, attempts=6):
        for attempt in range(attempts):
            try:
                self.request("GET", path, raw=True)
                return
            except ReconcileError as error:
                if "credential drift" in str(error):
                    raise
                if attempt == attempts - 1:
                    raise
                time.sleep(5)


def fields(resource):
    return {field["name"]: field.get("value") for field in resource.get("fields", [])}


def update_fields(resource, desired):
    result = deepcopy(resource)
    existing = {field["name"]: field for field in result.get("fields", [])}
    for name, value in desired.items():
        if name not in existing:
            raise ReconcileError(f"Application schema lacks required field: {name}")
        existing[name]["value"] = value
    return result


class Reconciler:
    def __init__(self, config, state_path, sonarr, qbittorrent, credentials):
        self.config = dict(config)
        self.state_path = Path(state_path)
        self.state = (
            json.loads(self.state_path.read_text())
            if self.state_path.exists()
            else {"owner": uuid.uuid4().hex[:16], "resources": {}}
        )
        self.sonarr = sonarr
        self.application = config.get("application", "sonarr")
        self.category_label = {"sonarr": "tv", "radarr": "movies", "lidarr": "music"}[
            self.application
        ]
        self.category_field = {
            "sonarr": "tvCategory",
            "radarr": "movieCategory",
            "lidarr": "musicCategory",
        }[self.application]
        self.api_prefix = "/api/v1" if self.application == "lidarr" else "/api/v3"
        self.category_key = self.category_label + "-category"
        self.client_key = self.application + "-client"
        self.qbittorrent = qbittorrent
        self.credentials = credentials
        self.changes = []

    def save(self):
        if not self.config["dryRun"]:
            write_json(self.state_path, self.state)

    def report(self, operation, resource, changed_fields):
        # Never include API responses, credential values, or desired payloads.
        self.changes.append(
            {
                "operation": operation,
                "resource": resource,
                "fields": sorted(changed_fields),
            }
        )

    def owned(self, key, name, matches):
        if len(matches) > 1:
            raise ReconcileError(f"Ambiguous objects for {key}; refusing mutation")
        record = self.state["resources"].get(key)
        if matches and record is None:
            raise ReconcileError(
                f"Unowned object conflicts with {key}; refusing adoption"
            )
        if record and record["name"] != name:
            raise ReconcileError(f"Ownership journal mismatch for {key}")
        if (
            matches
            and record.get("id") is not None
            and matches[0].get("id") != record["id"]
        ):
            raise ReconcileError(
                f"Object identity changed for {key}; refusing adoption"
            )
        return matches[0] if matches else None

    def intent(self, key, name, **metadata):
        # Persist intent and a random owner token BEFORE sending any write. An
        # interrupted POST can be recovered by its unique recorded name.
        self.state["resources"][key] = {"name": name, "pending": True, **metadata}
        self.save()

    def finish(self, key, resource_id=None):
        self.state["resources"][key].update(pending=False, id=resource_id)
        self.save()

    def category_name(self):
        return f"nixstead-{self.category_label}-{self.state['owner']}"

    def category(self):
        name = self.category_name()
        desired_path = self.config["categoryPath"]
        categories = self.qbittorrent.request("GET", "/api/v2/torrents/categories")
        current = self.owned(
            self.category_key, name, [categories[name]] if name in categories else []
        )
        if current is not None and current.get("savePath") == desired_path:
            if self.state["resources"][self.category_key].get("pending"):
                self.finish(self.category_key)
            return
        if current is not None:
            torrents = self.qbittorrent.request(
                "GET",
                "/api/v2/torrents/info?" + urllib.parse.urlencode({"category": name}),
            )
            if torrents and self.config["relocation"] != "allow":
                raise ReconcileError(
                    "Category path change affects existing torrents; choose relocation=allow explicitly"
                )
        self.report(
            "create" if current is None else "update", self.category_key, ["savePath"]
        )
        if self.config["dryRun"]:
            return
        self.intent(self.category_key, name)
        action = "createCategory" if current is None else "editCategory"
        self.qbittorrent.request(
            "POST",
            "/api/v2/torrents/" + action,
            {"category": name, "savePath": desired_path},
            form=True,
            raw=True,
        )
        self.finish(self.category_key)

    def root_folder(self):
        path = self.config["rootFolder"]
        roots = self.sonarr.request("GET", self.api_prefix + "/rootfolder")
        matches = [root for root in roots if root["path"] == path]
        if len(matches) > 1:
            raise ReconcileError("Ambiguous ARR root folders")
        if matches:
            if matches[0].get("accessible") is False:
                raise ReconcileError("Selected ARR root folder is inaccessible")
            # Existing root folders satisfy this relationship. No ownership or
            # modifications are applied to them or to existing series.
            return
        self.report("create", self.application + "-root-folder", ["path"])
        extra_fields = self.config.get("rootFields", {})
        if self.application == "lidarr":
            for field, endpoint in (
                ("defaultQualityProfileId", "qualityprofile"),
                ("defaultMetadataProfileId", "metadataprofile"),
            ):
                available = self.sonarr.request("GET", self.api_prefix + "/" + endpoint)
                if extra_fields.get(field) not in [
                    profile["id"] for profile in available
                ]:
                    raise ReconcileError(
                        "Explicit Lidarr profile selection is missing or invalid"
                    )
        if not self.config["dryRun"]:
            self.sonarr.request(
                "POST", self.api_prefix + "/rootfolder", {"path": path, **extra_fields}
            )

    def download_client(self):
        name = f"Nixstead qBittorrent {self.state['owner']}"
        clients = self.sonarr.request("GET", self.api_prefix + "/downloadclient")
        record = self.state["resources"].get(self.client_key, {})
        matches = [
            client
            for client in clients
            if client["name"] == name
            or (record.get("id") is not None and client.get("id") == record["id"])
        ]
        current = self.owned(self.client_key, name, matches)
        endpoint = urllib.parse.urlsplit(self.config["qbittorrentEndpoint"])
        desired = {
            "host": endpoint.hostname,
            "port": endpoint.port or (443 if endpoint.scheme == "https" else 80),
            "useSsl": endpoint.scheme == "https",
            "urlBase": endpoint.path.rstrip("/"),
            "username": self.credentials["username"],
            "password": self.credentials["password"],
            self.category_field: self.category_name(),
        }
        credential_digest = hashlib.sha256(
            (
                self.state["owner"]
                + "\0"
                + self.credentials["username"]
                + "\0"
                + self.credentials["password"]
            ).encode()
        ).hexdigest()
        if (
            current is not None
            and fields(current).get("password") == "********"
            and record.get("credentialDigest") == credential_digest
        ):
            # Sonarr deliberately masks stored passwords. Validate the stored
            # credential to detect UI drift without rewriting it every run.
            try:
                self.sonarr.request(
                    "POST", self.api_prefix + "/downloadclient/test", current
                )
            except ReconcileError:
                pass
            else:
                desired["password"] = "********"
        if current is None:
            schemas = self.sonarr.request(
                "GET", self.api_prefix + "/downloadclient/schema"
            )
            schemas = [
                schema
                for schema in schemas
                if schema["implementation"] == "QBittorrent"
            ]
            if len(schemas) != 1:
                raise ReconcileError("Missing or ambiguous ARR qBittorrent schema")
            resource = update_fields(schemas[0], desired)
            resource.update(name=name, enable=True)
        else:
            if current["implementation"] != "QBittorrent":
                raise ReconcileError(
                    "Owned download client has an unexpected implementation"
                )
            resource = update_fields(current, desired)
            resource.update(name=name, enable=True)
            if resource == current:
                if record.get("pending"):
                    self.finish(self.client_key, current["id"])
                return
        changed = [
            field
            for field, value in desired.items()
            if current is None or fields(current).get(field) != value
        ]
        changed += [
            field
            for field in ("name", "enable")
            if current is None or current.get(field) != resource[field]
        ]
        self.report("create" if current is None else "update", self.client_key, changed)
        if self.config["dryRun"]:
            return
        # Check actual connectivity before creating/updating the download client.
        self.sonarr.request("POST", self.api_prefix + "/downloadclient/test", resource)
        if current is None:
            self.intent(self.client_key, name, credentialDigest=credential_digest)
            result = self.sonarr.request(
                "POST", self.api_prefix + "/downloadclient", resource
            )
        else:
            result = self.sonarr.request(
                "PUT", f"{self.api_prefix}/downloadclient/{current['id']}", resource
            )
        self.state["resources"][self.client_key]["credentialDigest"] = credential_digest
        self.finish(self.client_key, result["id"])

    def run(self):
        preferences = self.qbittorrent.request("GET", "/api/v2/app/preferences")
        if Path(preferences.get("save_path", "")) != Path(self.config["torrentRoot"]):
            raise ReconcileError(
                "Effective qBittorrent save path conflicts with declared storage"
            )
        if self.config.get("incomplete") is not None and (
            not preferences.get("temp_path_enabled")
            or Path(preferences.get("temp_path", "")) != Path(self.config["incomplete"])
        ):
            raise ReconcileError(
                "Effective qBittorrent incomplete path conflicts with declared storage"
            )
        if not preferences.get("auto_tmm_enabled"):
            raise ReconcileError("qBittorrent automatic torrent management is disabled")
        self.save()
        if self.config["storageToQbittorrent"]:
            self.category()
        if self.config["downloadClient"]:
            if not self.config["storageToQbittorrent"]:
                existing = self.qbittorrent.request(
                    "GET", "/api/v2/torrents/categories"
                )
                if self.category_name() not in existing:
                    raise ReconcileError("The selected qBittorrent category is missing")
            self.root_folder()
            self.download_client()
        return self.changes


def publish_status(status_path, metrics_path, status):
    write_json(status_path, status)
    metrics = Path(metrics_path)
    metrics.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    text = f"nixstead_arr_reconciliation_success {int(status['success'])}\n"
    text += f"nixstead_arr_reconciliation_last_success_seconds {status.get('lastSuccess', 0)}\n"
    text += f"nixstead_arr_reconciliation_dry_run {int(status['dryRun'])}\n"
    temporary = metrics.with_suffix(".pending")
    temporary.write_text(text)
    temporary.chmod(0o644)
    temporary.replace(metrics)


def read_credential(directory, name):
    try:
        value = (directory / name).read_text().rstrip("\n")
    except OSError:
        value = ""
    if not value:
        raise ReconcileError(f"Awaiting credential setup: {name}")
    return value


def run_configuration(config, state_dir):
    credential_dir = Path(os.environ["CREDENTIALS_DIRECTORY"])
    credentials = {}
    qbittorrent = None
    if config["applications"]:
        credentials = {
            name: read_credential(credential_dir, name)
            for name in ("username", "password")
        }
        qbittorrent = API(config["qbittorrentEndpoint"])
        # systemd's running state precedes WebUI readiness while qBittorrent
        # restores its session. Wait on the public login page before sending
        # credentials; the version endpoint requires an authenticated session.
        qbittorrent.ready("/")
        reply = qbittorrent.request(
            "POST", "/api/v2/auth/login", credentials, form=True, raw=True
        )
        if reply.strip() not in ("Ok.", ""):
            raise ReconcileError(
                "qBittorrent credential drift; explicit repair required"
            )
        qbittorrent.ready("/api/v2/app/version")
    changes = []
    for application_config in config["applications"]:
        app_id = application_config["application"]
        application = None
        if application_config["downloadClient"]:
            application = API(
                application_config["endpoint"],
                read_credential(credential_dir, app_id),
            )
            prefix = "/api/v1" if app_id == "lidarr" else "/api/v3"
            application.ready(prefix + "/system/status")
        runner = Reconciler(
            application_config,
            state_dir / "ownership.json",
            application,
            qbittorrent,
            credentials,
        )
        changes.extend(runner.run())
    for desired in config.get("ntfy", []):
        from ntfy_adapter import ensure

        application = API(
            desired["applicationEndpoint"],
            read_credential(credential_dir, desired["application"]),
        )
        journal = Reconciler(
            {"application": desired["application"], "dryRun": config["dryRun"]},
            state_dir / "ownership.json",
            application,
            None,
            {},
        )
        journal.save()
        ensure(
            journal,
            application,
            desired,
            read_credential(credential_dir, "ntfy-" + desired["application"]),
            update_fields,
            fields,
            ReconcileError,
        )
        changes.extend(journal.changes)
    if config.get("seerr"):
        import runpy

        adapter = runpy.run_path(
            str(Path(__file__).parent.parent / "media/seerr_adapter.py")
        )["ensure"]
        seerr = API(
            config["seerr"]["endpoint"],
            read_credential(credential_dir, "seerr"),
        )
        seerr.ready("/api/v1/status")
        journal = Reconciler(
            {"dryRun": config["dryRun"]},
            state_dir / "ownership.json",
            None,
            None,
            {},
        )
        journal.save()
        key_names = [
            destination["application"]
            for destination in config["seerr"]["destinations"]
        ]
        if config["seerr"]["jellyfin"]:
            key_names.append("jellyfin")
        keys = {name: read_credential(credential_dir, name) for name in key_names}
        for destination in config["seerr"]["destinations"]:
            API(destination["endpoint"], keys[destination["application"]]).ready(
                "/api/v3/system/status"
            )
        jellyfin = None
        if config["seerr"]["jellyfin"]:
            jellyfin = API(
                config["seerr"]["jellyfin"]["endpoint"],
                keys["jellyfin"],
                key_header="X-Emby-Token",
            )
            jellyfin.ready("/System/Info")
        adapter(
            journal, seerr, config["seerr"], keys, ReconcileError, jellyfin=jellyfin
        )
        changes.extend(journal.changes)
    if config.get("sabnzbdApplications"):
        from sabnzbd_adapter import ensure

        sabnzbd = API(
            config["sabnzbdEndpoint"],
            read_credential(credential_dir, "sabnzbd"),
        )
        for desired in config["sabnzbdApplications"]:
            application = API(
                desired["endpoint"],
                read_credential(credential_dir, desired["application"]),
            )
            application.ready(
                ("/api/v1" if desired["application"] == "lidarr" else "/api/v3")
                + "/system/status"
            )
            journal = Reconciler(
                desired,
                state_dir / "ownership.json",
                application,
                None,
                {},
            )
            journal.save()
            ensure(
                journal,
                sabnzbd,
                application,
                desired,
                update_fields,
                fields,
                ReconcileError,
            )
            changes.extend(journal.changes)
    if config["prowlarrApplications"] or config.get("prowlarrSyncProfiles"):
        from prowlarr_adapter import ensure_applications, ensure_profiles

        prowlarr = API(
            config["prowlarrEndpoint"],
            read_credential(credential_dir, "prowlarr"),
        )
        prowlarr.ready("/api/v1/system/status")
        journal = Reconciler(
            {"dryRun": config["dryRun"]},
            state_dir / "ownership.json",
            None,
            None,
            {},
        )
        journal.save()
        keys = {
            entry["application"]: read_credential(credential_dir, entry["application"])
            for entry in config["prowlarrApplications"]
        }
        for entry in config["prowlarrApplications"]:
            API(entry["endpoint"], keys[entry["application"]]).ready(
                ("/api/v1" if entry["application"] == "lidarr" else "/api/v3")
                + "/system/status"
            )
        ensure_profiles(journal, prowlarr, config.get("prowlarrSyncProfiles", {}))
        ensure_applications(
            journal,
            prowlarr,
            config["prowlarrApplications"],
            keys,
            update_fields,
            fields,
            ReconcileError,
        )
        changes.extend(journal.changes)
    if config.get("bazarrApplications"):
        from bazarr_adapter import ensure_connections

        bazarr = API(
            config["bazarrEndpoint"],
            read_credential(credential_dir, "bazarr"),
        )
        bazarr.ready("/api/system/status")
        journal = Reconciler(
            {"dryRun": config["dryRun"]},
            state_dir / "ownership.json",
            None,
            None,
            {},
        )
        journal.save()
        keys = {
            entry["application"]: read_credential(credential_dir, entry["application"])
            for entry in config["bazarrApplications"]
        }
        for entry in config["bazarrApplications"]:
            API(entry["endpoint"], keys[entry["application"]]).ready(
                "/api/v3/system/status"
            )
        ensure_connections(
            journal, bazarr, config["bazarrApplications"], keys, ReconcileError
        )
        changes.extend(journal.changes)
    return changes


def relationship_configs(config):
    """Isolate failures while retaining the common application write lock."""
    base = deepcopy(config)
    groups = [
        "applications",
        "ntfy",
        "sabnzbdApplications",
        "prowlarrApplications",
        "bazarrApplications",
    ]
    for group in groups:
        base[group] = []
    base["seerr"] = None
    base["prowlarrSyncProfiles"] = {}
    if config.get("prowlarrSyncProfiles"):
        selected = deepcopy(base)
        selected["prowlarrSyncProfiles"] = deepcopy(config["prowlarrSyncProfiles"])
        yield "prowlarr:profiles", selected
    for group in groups:
        for desired in config.get(group, []):
            selected = deepcopy(base)
            selected[group] = [deepcopy(desired)]
            yield group + ":" + desired.get("application", "sonarr"), selected
    if config.get("seerr"):
        seerr = config["seerr"]
        for destination in seerr["destinations"]:
            selected = deepcopy(base)
            selected["seerr"] = dict(
                deepcopy(seerr), jellyfin=None, destinations=[deepcopy(destination)]
            )
            yield "seerr:" + destination["application"], selected
        if seerr.get("jellyfin"):
            selected = deepcopy(base)
            selected["seerr"] = dict(deepcopy(seerr), destinations=[])
            yield "seerr:jellyfin", selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument(
        "--state-dir", type=Path, default=Path("/var/lib/nixstead-arr-integrations")
    )
    args = parser.parse_args()
    config = json.loads(args.configuration.read_text())
    args.state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (args.state_dir / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        status_path = args.state_dir / "status.json"
        status = json.loads(status_path.read_text()) if status_path.exists() else {}
        previous = status.get("relationships", {})
        status.update(
            lastAttempt=time.time(),
            desiredHash=hashlib.sha256(args.configuration.read_bytes()).hexdigest(),
            dryRun=config["dryRun"],
            success=False,
            lastError="Reconciliation has started but has not completed",
            changes=[],
            relationships={},
        )
        publish_status(status_path, config["metricsFile"], status)
        for name, desired in relationship_configs(config):
            result = {"lastAttempt": time.time()}
            if previous.get(name, {}).get("lastSuccess") is not None:
                result["lastSuccess"] = previous[name]["lastSuccess"]
            try:
                changes = run_configuration(desired, args.state_dir)
                status["changes"].extend(changes)
                result.update(success=True, lastError=None)
                if not config["dryRun"]:
                    result["lastSuccess"] = time.time()
            except Exception as error:
                message = (
                    str(error)
                    if isinstance(error, ReconcileError)
                    else "Reconciliation failed; check runtime state and credential availability"
                )
                result.update(success=False, lastError=message)
            status["relationships"][name] = result
            publish_status(status_path, config["metricsFile"], status)
        errors = [
            name + ": " + value["lastError"]
            for name, value in status["relationships"].items()
            if not value["success"]
        ]
        status.update(
            success=not errors, lastError="; ".join(errors) if errors else None
        )
        if not errors and not config["dryRun"]:
            status["lastSuccess"] = time.time()
        publish_status(status_path, config["metricsFile"], status)
        print(
            json.dumps(
                {"changes": status["changes"], "relationships": status["relationships"]}
            )
        )
        raise SystemExit(0 if status["success"] else 1)


if __name__ == "__main__":
    main()
