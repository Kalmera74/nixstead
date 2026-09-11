"""Native account/chat/upload APIs; secrets and original signed tokens stay in VM."""

import json
from pathlib import Path
import secrets
import socket
import sys
import time
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

if sys.argv[1] == "generate":
    print(
        json.dumps(
            {
                "fixture": {
                    name + "Password": secrets.token_hex(24)
                    for name in ["admin", "user", "other"]
                }
            }
        )
    )
    raise SystemExit

BASE = "http://127.0.0.1:28081"
EVIDENCE = Path("/var/lib/openwebui-fixture-evidence")
KEY = Path("/var/lib/open-webui/.webui_secret_key")
PROMPT = "Once upon a time, there was a little"
UPLOAD = bytes(range(256)) * 64 + b"Original uploaded bytes\n"


def call(
    method, path, payload=None, *, token=None, status=200, raw=False, content_type=None
):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = payload if raw else None if payload is None else json.dumps(payload).encode()
    if data is not None:
        headers["Content-Type"] = content_type or "application/json"
    try:
        response = urlopen(
            Request(BASE + path, data=data, method=method, headers=headers), timeout=90
        )
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == status, (method, path, response.status, status)
        if raw or status != 200:
            return body
        return json.loads(body) if body else None


def account(name):
    return {
        "email": name + "@fixture.test",
        "name": "Fixture " + name,
        "password": Path("/run/secrets/fixture/" + name + "Password")
        .read_text()
        .strip(),
    }


def login(name):
    values = account(name)
    return call(
        "POST",
        "/api/v1/auths/signin",
        {"email": values["email"], "password": values["password"]},
    )


def saved():
    return json.loads((EVIDENCE / "expected.json").read_text())


def generate(token, model, status=200):
    result = call(
        "POST",
        "/api/chat/completions",
        {
            "model": model,
            "messages": [{"role": "user", "content": PROMPT}],
            "stream": False,
            "max_tokens": 16,
            "temperature": 0,
            "seed": 42,
            "options": {
                "num_predict": 16,
                "num_ctx": 128,
                "num_thread": 1,
                "temperature": 0,
                "seed": 42,
            },
        },
        token=token,
        status=status,
    )
    if status != 200:
        return
    content = result["choices"][0]["message"]["content"]
    assert any(c.isalpha() for c in content), "Native model produced no text"
    return content


def populate():
    admin = call("POST", "/api/v1/auths/signup", account("admin"))
    assert admin["role"] == "admin"
    user = call(
        "POST",
        "/api/v1/auths/add",
        {**account("user"), "role": "user"},
        token=admin["token"],
    )
    other = call(
        "POST",
        "/api/v1/auths/add",
        {**account("other"), "role": "user"},
        token=admin["token"],
    )
    assert user["role"] == other["role"] == "user"
    models = call("GET", "/api/models?refresh=true", token=admin["token"])["data"]
    model = next(
        value["id"]
        for value in models
        if value["id"].endswith("fixture-stories:latest")
    )
    # Native WebUI hides unconfigured base models from regular users. Grant
    # only this user read access through the actual model administration API.
    assert model not in [
        value["id"] for value in call("GET", "/api/models", token=user["token"])["data"]
    ]
    call(
        "POST",
        "/api/v1/models/create",
        {
            "id": model,
            "name": "Private fixture model",
            "meta": {"description": "Explicit single-user inference grant"},
            "params": {"temperature": 0},
            "access_grants": [
                {
                    "principal_type": "user",
                    "principal_id": user["id"],
                    "permission": "read",
                }
            ],
        },
        token=admin["token"],
    )
    assert model in [
        value["id"]
        for value in call("GET", "/api/models?refresh=true", token=user["token"])[
            "data"
        ]
    ]
    response = generate(user["token"], model)
    messages = {
        "fixture-question": {
            "id": "fixture-question",
            "parentId": None,
            "childrenIds": ["fixture-answer"],
            "role": "user",
            "content": PROMPT,
            "timestamp": int(time.time()),
        },
        "fixture-answer": {
            "id": "fixture-answer",
            "parentId": "fixture-question",
            "childrenIds": [],
            "role": "assistant",
            "content": response,
            "model": model,
            "done": True,
            "timestamp": int(time.time()),
        },
    }
    chat = {
        "title": "Persisted native model conversation",
        "models": [model],
        "history": {"messages": messages, "currentId": "fixture-answer"},
        "messages": list(messages.values()),
        "params": {"temperature": 0},
    }
    created = call("POST", "/api/v1/chats/new", {"chat": chat}, token=user["token"])
    boundary = "nixstead-fixture-multipart"
    multipart = (
        (
            "--"
            + boundary
            + '\r\nContent-Disposition: form-data; name="file"; filename="fixture-original.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'
        ).encode()
        + UPLOAD
        + ("\r\n--" + boundary + "--\r\n").encode()
    )
    uploaded_bytes = call(
        "POST",
        "/api/v1/files/?process=false",
        multipart,
        token=user["token"],
        raw=True,
        content_type="multipart/form-data; boundary=" + boundary,
    )
    uploaded = json.loads(uploaded_bytes)
    expected = {
        "accounts": {"admin": admin, "user": user, "other": other},
        "model": model,
        "chat_id": created["id"],
        "chat": chat,
        "file_id": uploaded["id"],
    }
    (EVIDENCE / "expected.json").write_text(json.dumps(expected))
    (EVIDENCE / "expected.json").chmod(0o600)
    (EVIDENCE / "original-key").write_bytes(KEY.read_bytes())
    (EVIDENCE / "original-key").chmod(0o600)
    (EVIDENCE / "unrelated").write_text("Keep unrelated state\n")
    call(
        "POST",
        "/api/v1/auths/signin",
        {"email": account("user")["email"], "password": "invalid-disposable-password"},
        status=400,
    )


def verify():
    expected = saved()
    for name, original in expected["accounts"].items():
        current = call("GET", "/api/v1/auths/", token=original["token"])
        assert (current["id"], current["role"], current["name"]) == (
            original["id"],
            original["role"],
            original["name"],
        ), name
    assert login("user")["id"] == expected["accounts"]["user"]["id"]
    token = expected["accounts"]["user"]["token"]
    other = expected["accounts"]["other"]["token"]
    model_path = "/api/v1/models/model?id=" + quote(expected["model"], safe="")
    model = call("GET", model_path, token=token)
    assert model["name"] == "Private fixture model" and not model["write_access"]
    assert model["meta"]["description"] == "Explicit single-user inference grant"
    call("GET", model_path, token=other, status=401)
    chat = call("GET", "/api/v1/chats/" + expected["chat_id"], token=token)
    assert chat["user_id"] == expected["accounts"]["user"]["id"]
    for field, value in expected["chat"].items():
        assert chat["chat"][field] == value, field
    content = call(
        "GET",
        "/api/v1/files/" + expected["file_id"] + "/content",
        token=token,
        raw=True,
    )
    assert content == UPLOAD
    assert KEY.read_bytes() == (EVIDENCE / "original-key").read_bytes()
    assert (EVIDENCE / "unrelated").read_text() == "Keep unrelated state\n"
    call("GET", "/api/v1/chats/", status=401)
    call("GET", "/api/v1/chats/" + expected["chat_id"], token=other, status=401)
    call(
        "GET",
        "/api/v1/files/" + expected["file_id"] + "/content",
        token=other,
        status=404,
    )
    call("GET", "/api/v1/auths/admin/config", token=token, status=401)


def infer():
    expected = saved()
    generate(expected["accounts"]["user"]["token"], expected["model"])


def unavailable():
    expected = saved()
    generate(expected["accounts"]["user"]["token"], expected["model"], status=400)


def interrupt_upload():
    token = saved()["accounts"]["user"]["token"]
    before = call("GET", "/api/v1/files/", token=token)
    boundary = "nixstead-interrupted-upload"
    multipart = (
        (
            "--"
            + boundary
            + '\r\nContent-Disposition: form-data; name="file"; filename="fixture-interrupted.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'
        ).encode()
        + UPLOAD
        + ("\r\n--" + boundary + "--\r\n").encode()
    )
    headers = (
        "POST /api/v1/files/?process=false HTTP/1.1\r\n"
        "Host: 127.0.0.1:28081\r\n"
        "Connection: close\r\n"
        "Authorization: Bearer " + token + "\r\n"
        "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n"
        "Content-Length: " + str(len(multipart)) + "\r\n\r\n"
    ).encode()
    with socket.create_connection(("127.0.0.1", 28081), timeout=10) as connection:
        connection.sendall(headers + multipart[: len(multipart) // 2])
        connection.shutdown(socket.SHUT_WR)
        # A disconnected incomplete request may close without an HTTP response.
        while connection.recv(4096):
            pass
    assert call("GET", "/api/v1/files/", token=token) == before
    uploaded = json.loads(
        call(
            "POST",
            "/api/v1/files/?process=false",
            multipart,
            token=token,
            raw=True,
            content_type="multipart/form-data; boundary=" + boundary,
        )
    )
    assert (
        call(
            "GET",
            "/api/v1/files/" + uploaded["id"] + "/content",
            token=token,
            raw=True,
        )
        == UPLOAD
    )


{
    "populate": populate,
    "verify": verify,
    "infer": infer,
    "unavailable": unavailable,
    "interrupt-upload": interrupt_upload,
}[sys.argv[1]]()
print("Open WebUI fixture " + sys.argv[1] + " succeeded")
