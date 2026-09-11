"""Deliver deployed SOPS credentials without modifying the encrypted source."""

import argparse
import base64
import fcntl
import hashlib
import http.cookiejar
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

import yaml
from configobj import ConfigObj


def valid_key(value):
    return (
        isinstance(value, str)
        and re.fullmatch(r"[A-Za-z0-9_+/-]{16,}={0,2}", value) is not None
    )


def extract(source, format_name, reader=None, allow_missing=False):
    text = (reader or (lambda path: Path(path).read_text()))(source)
    if format_name == "raw":
        value = text.strip()
    elif format_name == "xml":
        value = ET.fromstring(text).findtext("ApiKey", "")
    elif format_name == "seerr":
        value = json.loads(text).get("main", {}).get("apiKey", "")
    elif format_name == "ini":
        value = (
            ConfigObj(io.StringIO(text), encoding="utf-8")
            .get("misc", {})
            .get("api_key", "")
        )
    elif format_name == "yaml":
        value = yaml.safe_load(text).get("auth", {}).get("apikey", "")
    else:
        raise ValueError("Unsupported credential parser")
    if allow_missing and value in (None, "", "replace-me"):
        return None
    if not valid_key(value):
        raise ValueError("Application key is absent or malformed")
    return value


def atomic_write(path, content, mode=0o400):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".pending-")
    try:
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        parent_fd = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
    finally:
        Path(temporary).unlink(missing_ok=True)


def environment_line(name, value):
    # systemd EnvironmentFile supports quoted values, including passwords with
    # spaces, quotes, backslashes, dollar signs and percent signs.
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("$", "\\$")
        .replace("`", "\\`")
    )
    return f'{name}="{escaped}"\n'


def deployed_values(config):
    document_path = Path(config["document"])
    document = (
        yaml.safe_load(document_path.read_text()) if document_path.exists() else {}
    )
    if not isinstance(document, dict):
        raise ValueError("Invalid deployed credential document")
    values = {}
    for field, source in config["keys"].items():
        if source.get("file"):
            value = Path(source["file"]).read_text().rstrip("\n")
        else:
            value = document
            for part in source["path"].split("/"):
                if value is None:
                    break
                if not isinstance(value, dict):
                    raise ValueError("Invalid deployed credential branch")
                value = value.get(part)
        if value in (None, "", "replace-me"):
            value = ""
        elif (
            not isinstance(value, str)
            or any(c in value for c in "\r\n\0")
            or (field == "api-key" and not valid_key(value))
        ):
            raise ValueError("Invalid deployed credential")
        values[field] = value
    values["revision"] = str(
        (document.get(config["service"]) or {}).get("credentialRevision", "")
    )
    return values


def publish(config):
    root = Path(config["outputs"][0]["path"]).parent
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (root / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        publish_locked(config)


def publish_locked(config):
    values = deployed_values(config)
    ready = all(values[field] for field in config["keys"])
    outputs = {}
    for output in config["outputs"]:
        path = Path(output["path"])
        if output.get("ini"):
            content = "[misc]\napi_key = " + values["api-key"] + "\n" if ready else ""
        elif "environment" in output:
            content = (
                "".join(
                    environment_line(name, values[key])
                    for name, key in output["environment"].items()
                )
                if ready or not output.get("optional")
                else ""
            )
        else:
            content = output.get("prefix", "") + values[output["key"]] + "\n"
        outputs[path] = content
    pending = next(iter(outputs)).parent / "delivery-pending"
    ready_path = pending.parent / "ready"
    action = "restart" if ready else "try-restart"
    changed = any(
        not path.exists() or path.read_text() != content
        for path, content in outputs.items()
    )
    if changed or pending.exists():
        atomic_write(pending, action + "\n")
        for path, content in outputs.items():
            if not path.exists() or path.read_text() != content:
                atomic_write(path, content)
        if ready:
            atomic_write(ready_path, "ready\n")
        else:
            ready_path.unlink(missing_ok=True)
        for unit in config["consumers"]:
            subprocess.run(
                ["systemctl", "--no-block", action, unit],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        pending.unlink()
    print(
        "Deployed SOPS credentials delivered"
        if ready
        else "Awaiting credential setup: run nixstead credentials sync"
    )


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Unexpected application redirect")


def verify_application(service, entry, values):
    """Read-only authenticated check; never return API payloads or key values."""
    host = "http://127.0.0.1:" + str(entry["settings"]["port"])
    paths = {
        "sonarr": "/api/v3/system/status",
        "radarr": "/api/v3/system/status",
        "lidarr": "/api/v1/system/status",
        "prowlarr": "/api/v1/system/status",
        "bazarr": "/api/system/status",
        "seerr": "/api/v1/settings/main",
        "sabnzbd": "/api?mode=queue&output=json",
    }
    headers = {"Referer": host}
    data = None
    if service == "qbittorrent":
        url = host + "/api/v2/auth/login"
        data = urllib.parse.urlencode(values).encode()
    else:
        url = host + paths[service]
        if service == "sabnzbd":
            data = urllib.parse.urlencode({"apikey": values["api-key"]}).encode()
        else:
            headers["X-Api-Key"] = values["api-key"]
    try:
        opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            NoRedirect(),
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),
        )
        with opener.open(
            urllib.request.Request(url, headers=headers, data=data), timeout=5
        ) as response:
            body = response.read(4 * 1024 * 1024)
            if service == "qbittorrent":
                if body.strip() not in (b"Ok.", b""):
                    return "application drift"
                # qBittorrent versions differ in login response bodies. Confirm
                # the session on a protected endpoint rather than guessing.
                with opener.open(
                    host + "/api/v2/app/version", timeout=5
                ) as authenticated:
                    if not authenticated.read(1024).strip():
                        return "not yet checked"
            if service == "sabnzbd" and json.loads(body).get("error"):
                return "application drift"
        return "in sync"
    except urllib.error.HTTPError as error:
        error.close()
        return "application drift" if error.code in (401, 403) else "not yet checked"
    except (OSError, ValueError):
        return "not yet checked"


def install_qbittorrent(path):
    directory = Path(os.environ["CREDENTIALS_DIRECTORY"])
    username = (directory / "username").read_text().rstrip("\n")
    password = (directory / "password").read_text().rstrip("\n")
    if not username or not password:
        print(
            "Awaiting qBittorrent credential setup; keeping application bootstrap authentication"
        )
        return
    if any(c in username + password for c in "\r\n\0"):
        raise ValueError("Invalid qBittorrent credential")
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha512", password.encode(), salt, 100000)
    encoded = (
        "@ByteArray("
        + base64.b64encode(salt).decode()
        + ":"
        + base64.b64encode(digest).decode()
        + ")"
    )
    # QSettings uses quoted INI strings and reserves a leading @ for types.
    username = username.replace("\\", "\\\\").replace('"', '\\"')
    if username.startswith("@"):
        username = "@" + username
    with Path(path).open("a") as stream:
        stream.write(
            f'\n[Preferences]\nWebUI\\Username="{username}"\nWebUI\\Password_PBKDF2={encoded}\n'
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path, nargs="?")
    parser.add_argument("--qbittorrent", type=Path)
    args = parser.parse_args()
    try:
        if args.qbittorrent:
            install_qbittorrent(args.qbittorrent)
        elif args.configuration:
            publish(json.loads(args.configuration.read_text()))
        else:
            parser.error("a configuration is required")
    except Exception:
        raise SystemExit(
            "Credential delivery failed; check SOPS source availability and format"
        ) from None


if __name__ == "__main__":
    main()
