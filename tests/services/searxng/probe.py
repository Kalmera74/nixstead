#!/usr/bin/env python3
"""Deterministic JSON engine and SearXNG application probe."""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

FIXTURE_ADDRESS = ("127.0.0.2", 18082)
MODE_FILE = Path("/var/lib/searxng-engine-fixture/mode")
SEARCH_URL = "http://127.0.0.1:28191/search"
QUERY = "nixstead bounded search"
RESULT = {
    "url": "https://fixture.example.test/result/nixstead-bounded-search",
    "title": "Nixstead deterministic result",
    "content": "Exact local engine bytes: nixstead bounded search",
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, _format, *_args):
        return

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/search":
            self.send_error(404)
            return
        mode = MODE_FILE.read_text().strip() if MODE_FILE.exists() else "ok"
        if mode == "unavailable":
            self.send_error(503)
            return
        if mode == "malformed":
            body = b'{"results":['
        else:
            query = urllib.parse.parse_qs(parsed.query).get("q", [""])[0]
            body = json.dumps(
                {
                    "results": [
                        {
                            "url": "https://fixture.example.test/result/"
                            + query.replace(" ", "-"),
                            "title": "Nixstead deterministic result",
                            "snippet": f"Exact local engine bytes: {query}",
                        }
                    ]
                }
            ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def serve():
    MODE_FILE.parent.mkdir(parents=True, exist_ok=True)
    MODE_FILE.write_text("ok\n")
    ThreadingHTTPServer(FIXTURE_ADDRESS, Handler).serve_forever()


def request(query=QUERY):
    url = (
        SEARCH_URL
        + "?"
        + urllib.parse.urlencode({"q": query, "engines": "fixture", "format": "json"})
    )
    browser_request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Firefox/142.0",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(browser_request, timeout=10) as response:
        return json.load(response)


def verify():
    payload = request()
    assert payload["query"] == QUERY, payload
    assert len(payload["results"]) == 1, payload
    result = payload["results"][0]
    for key, value in RESULT.items():
        assert result[key] == value, result
    assert result["engine"] == "fixture", result
    assert not payload["unresponsive_engines"], payload


def expect_engine_failure():
    payload = request()
    assert payload["results"] == [], payload
    failed = [entry[0] for entry in payload["unresponsive_engines"]]
    assert failed == ["fixture"], payload


def set_mode(mode):
    if mode not in {"ok", "malformed", "unavailable"}:
        raise ValueError(mode)
    MODE_FILE.write_text(mode + "\n")


if __name__ == "__main__":
    command = sys.argv[1]
    if command == "serve":
        serve()
    elif command == "verify":
        verify()
    elif command == "expect-engine-failure":
        expect_engine_failure()
    elif command == "mode":
        set_mode(sys.argv[2])
    else:
        raise SystemExit(f"unknown command: {command}")
