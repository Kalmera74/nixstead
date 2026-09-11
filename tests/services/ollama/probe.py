"""Use Ollama's real blob/import/generation APIs with an immutable local model."""

import hashlib
import json
from pathlib import Path
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen


BASE = "http://127.0.0.1:21434"
MODEL = "fixture-stories:latest"
EVIDENCE = Path("/var/lib/ollama-fixture")


def request(path, data=None, *, status=200, raw=False, method=None):
    if data is not None and not raw:
        data = json.dumps(data).encode()
    query = Request(
        BASE + path,
        data=data,
        headers={
            "Content-Type": "application/octet-stream" if raw else "application/json"
        },
        method=method,
    )
    try:
        response = urlopen(query, timeout=120)
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == status, (response.status, body)
    return json.loads(body) if body else None


def import_model():
    data = Path("/etc/ollama-fixture-model").read_bytes()
    digest = "sha256:" + hashlib.sha256(data).hexdigest()
    request("/api/blobs/" + digest, data, raw=True, status=201)
    result = request(
        "/api/create",
        {
            "model": MODEL,
            "files": {"stories.gguf": digest},
            "template": "{{ .Prompt }}",
            "parameters": {
                "num_ctx": 128,
                "num_predict": 16,
                "temperature": 0,
                "seed": 42,
            },
            "stream": False,
        },
    )
    assert result["status"] == "success"


def generate():
    result = request(
        "/api/generate",
        {
            "model": MODEL,
            "prompt": "Once upon a time, there was a little",
            "raw": True,
            "stream": False,
            "keep_alive": 0,
            "options": {
                "num_predict": 16,
                "num_ctx": 128,
                "num_thread": 1,
                "temperature": 0,
                "seed": 42,
            },
        },
    )
    assert result["done"] and 0 < result["eval_count"] <= 16
    assert result["prompt_eval_count"] > 0
    assert any(c.isalpha() for c in result["response"])
    return result["response"]


def verify():
    expected = json.loads((EVIDENCE / "expected.json").read_text())
    assert generate() == expected["response"]
    model = next(
        item for item in request("/api/tags")["models"] if item["name"] == MODEL
    )
    assert model["digest"] == expected["digest"]
    show = request("/api/show", {"model": MODEL})
    assert show["template"] == "{{ .Prompt }}"
    assert "num_ctx" in show["parameters"] and "128" in show["parameters"]


def failures():
    request("/api/generate", b"{invalid", raw=True, status=400)
    request("/api/generate", {"model": "absent-fixture", "stream": False}, status=404)
    # Importing an incompatible, correctly hashed blob must not create a model.
    invalid = b"Not a GGUF model\n"
    digest = "sha256:" + hashlib.sha256(invalid).hexdigest()
    request("/api/blobs/" + digest, invalid, raw=True, status=201)
    result = request(
        "/api/create",
        {
            "model": "invalid-fixture",
            "files": {"invalid.gguf": digest},
            "stream": False,
        },
        status=400,
    )
    assert result.get("error")
    # Bounded failed acquisition from a refused local registry, with no internet.
    result = request(
        "/api/pull",
        {
            "model": "127.0.0.1:29999/library/missing:latest",
            "insecure": True,
            "stream": False,
        },
        status=500,
    )
    assert "connection refused" in result["error"]
    assert not any(
        item["name"].startswith("invalid-fixture")
        for item in request("/api/tags")["models"]
    )
    verify()


action = sys.argv[1]
if action == "populate":
    EVIDENCE.mkdir(mode=0o700, exist_ok=True)
    import_model()
    response = generate()
    digest = next(
        item["digest"]
        for item in request("/api/tags")["models"]
        if item["name"] == MODEL
    )
    (EVIDENCE / "expected.json").write_text(
        json.dumps({"response": response, "digest": digest})
    )
elif action == "verify":
    verify()
elif action == "failures":
    failures()
elif action == "reconstruct":
    assert not request("/api/tags")["models"]
    import_model()
    verify()
else:
    raise SystemExit("Unknown Ollama fixture action")
