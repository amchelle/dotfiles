#!/usr/bin/env python3
"""Exercise the real Preflight proxy against a recording local upstream."""
import base64
import json
import os
from pathlib import Path
import shutil
import sys
import socket
import subprocess
import tempfile
import threading
import struct
import zlib
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


TOKEN = "ghp_" + "aB39" * 9
CLIENT_KEY = "synthetic-client-key"


def png(metadata=None):
    def chunk(kind, data):
        return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))
    image = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!2I5B", 100, 100, 8, 2, 0, 0, 0))
    if metadata:
        image += chunk(b"tEXt", b"Comment\0" + metadata.encode())
    return image + chunk(b"IDAT", zlib.compress((b"\0" + b"\xff" * 300) * 100)) + chunk(b"IEND", b"")


def pdf(metadata=None):
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>",
               b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R /Resources << >> >>",
               b"<< /Length 0 >>\nstream\n\nendstream",
               b"<< /Subject (" + (metadata or "ordinary document").encode() + b") >>"]
    data = b"%PDF-1.4\n"
    offsets = [0]
    for number, obj in enumerate(objects, 1):
        offsets.append(len(data))
        data += f"{number} 0 obj\n".encode() + obj + b"\nendobj\n"
    xref = len(data)
    data += b"xref\n0 6\n0000000000 65535 f \n"
    data += b"".join(f"{offset:010d} 00000 n \n".encode() for offset in offsets[1:])
    return data + f"trailer\n<< /Size 6 /Root 1 0 R /Info 5 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Upstream(ThreadingHTTPServer):
    daemon_threads = True
    requests = []
    lock = threading.Lock()
    stream_release = threading.Event()
    stream_timed_out = False


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        with self.server.lock:
            self.server.requests.append((self.path, {k.lower(): v for k, v in self.headers.items()}, body))
        payload = b'data: {"id":"smoke","choices":[]}\n\ndata: [DONE]\n\n'
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        if self.headers.get("x-smoke-stream"):
            first, rest = payload.split(b"\n\n", 1)
            self.wfile.write(first + b"\n\n")
            self.wfile.flush()
            self.server.stream_timed_out = not self.server.stream_release.wait(timeout=5)
            self.wfile.write(rest)
        else:
            self.wfile.write(payload)

    def do_GET(self):
        with self.server.lock:
            self.server.requests.append((self.path, dict(self.headers), b""))
        payload = b'{"data":[{"id":"smoke-model"}]}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass


def call(url, body=None, headers=None, method=None, authenticated=True, timeout=15):
    headers = {"Authorization": "Bearer " + CLIENT_KEY, **(headers or {})} if authenticated else (headers or {})
    request = Request(url, data=body, headers=headers, method=method)
    try:
        with urlopen(request, timeout=timeout) as response:
            return response.status, response.headers, response.read()
    except HTTPError as error:
        return error.code, error.headers, error.read()


def sandbox_check(binary, root, upstream_port):
    profile = Path(shutil.which(binary) or binary).resolve().parent.parent / "share/preflight/preflight.sb"
    job = root / "sandbox-job"
    job.mkdir()
    private = root / "private-fixture"
    private.write_text("synthetic private data")
    probe = '''import pathlib, socket, sys
job, private, outside = map(pathlib.Path, sys.argv[1:4])
(job / "allowed").write_text("safe")
checks = [lambda: private.read_bytes(), lambda: outside.write_text("unsafe"),
          lambda: socket.create_connection(("127.0.0.1", int(sys.argv[4])), timeout=1)]
for action in checks:
    try:
        action()
    except PermissionError:
        pass
    else:
        raise SystemExit("sandbox boundary escaped")
'''
    subprocess.run(["/usr/bin/sandbox-exec", "-D", "JOBDIR=" + str(job.resolve()), "-f", str(profile),
                    str(Path(sys.executable).resolve()), "-c", probe,
                    str(job.resolve()), str(private.resolve()), str(root / "outside-write"), str(upstream_port)],
                   check=True, timeout=10)


def main():
    binary = os.environ.get("PREFLIGHT_BIN", "preflight")
    upstream = Upstream(("127.0.0.1", 0), Handler)
    port, upstream_port = free_port(), upstream.server_port
    thread = threading.Thread(target=upstream.serve_forever, daemon=True)
    thread.start()
    with tempfile.TemporaryDirectory(prefix="preflight-smoke-") as directory:
        root = Path(directory)
        sandbox_check(binary, root, upstream_port)
        (root / "cache").mkdir(mode=0o700)
        config = root / "config.toml"
        config.write_text(
            f'bind = "127.0.0.1:{port}"\n'
            f'upstream = "http://127.0.0.1:{upstream_port}"\n'
            'mode = "redact"\nsandbox = false\n'
            f'cache_dir = "{root / "cache"}"\n'
            f'control_socket = "{root / "control.sock"}"\n',
            encoding="utf-8",
        )
        log_path = root / "preflight.log"
        environment = {k: v for k, v in os.environ.items() if not k.startswith("PREFLIGHT_")}
        environment.update(RUST_LOG="info", PREFLIGHT_CLIENT_KEY=CLIENT_KEY, NO_PROXY="127.0.0.1,localhost")
        with log_path.open("wb") as log:
            process = subprocess.Popen(
                [binary, "serve", "--config", str(config)], stdout=log,
                stderr=subprocess.STDOUT, env=environment,
            )
            base = f"http://127.0.0.1:{port}"
            try:
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise AssertionError(f"Preflight exited with {process.returncode}: {log_path.read_text()}")
                    try:
                        status, _, _ = call(base + "/readyz")
                        if status == 200:
                            break
                    except (URLError, TimeoutError):
                        time.sleep(0.1)
                else:
                    raise AssertionError("Preflight did not become ready")

                before = len(upstream.requests)
                status, _, _ = call(base + "/v1/models", authenticated=False)
                assert status == 401 and len(upstream.requests) == before
                # Clean payloads are forwarded byte-for-byte, including whitespace.
                clean = b'{ "model" : "smoke-model", "messages" : [{"role":"user","content":"hello"}], "stream":true }'
                status, _, response = call(base + "/v1/chat/completions", clean, {
                    "Content-Type": "application/json",
                    "x-session-id": "session-smoke", "x-codex-turn-id": "turn-smoke",
                })
                assert status == 200 and response == b'data: {"id":"smoke","choices":[]}\n\ndata: [DONE]\n\n'
                first = upstream.requests[-1]
                assert first[0] == "/v1/chat/completions" and first[2] == clean
                assert first[1].get("authorization") == "Bearer " + CLIENT_KEY
                assert first[1].get("x-session-id") == "session-smoke"
                assert first[1].get("x-codex-turn-id") == "turn-smoke"
                assert first[1].get("x-request-id")

                request = Request(base + "/v1/responses", data=clean, headers={
                    "Authorization": "Bearer " + CLIENT_KEY, "x-smoke-stream": "yes"})
                with urlopen(request, timeout=15) as streamed:
                    first_event = streamed.readline() + streamed.readline()
                    assert first_event == b'data: {"id":"smoke","choices":[]}\n\n'
                    assert not upstream.stream_timed_out, "response was buffered instead of streamed"
                    upstream.stream_release.set()
                    assert streamed.read() == b"data: [DONE]\n\n"

                nested = {"model": "smoke-model", "messages": [
                    {"role": "user", "content": "credential " + TOKEN},
                    {"role": "assistant", "tool_calls": [{"id": "call-1", "type": "function",
                     "function": {"name": "inspect", "arguments": json.dumps({"nested": TOKEN})}}]},
                    {"role": "tool", "content": json.dumps({"result": TOKEN})},
                ]}
                before = len(upstream.requests)
                status, _, _ = call(base + "/v1/chat/completions", json.dumps(nested).encode(),
                                    {"Content-Type": "application/json"})
                assert status == 200
                forwarded = json.loads(upstream.requests[before][2])
                serialized = json.dumps(forwarded)
                assert TOKEN not in serialized and "[REDACTED:github-pat]" in serialized

                # OMP uses Responses, not just Chat Completions.
                clean_responses = b'{ "model":"smoke-model", "input":"ordinary source code", "stream":true }'
                status, headers, response = call(base + "/v1/responses", clean_responses)
                assert status == 200 and response.endswith(b"data: [DONE]\n\n")
                assert upstream.requests[-1][2] == clean_responses
                assert headers.get("x-preflight-finding-count") == "0"

                # Exercise the actual sandboxed OCR/metadata worker, including a
                # sanitized image whose metadata contains a synthetic PAT.
                for metadata in (None, TOKEN):
                    attachment = {"model": "smoke-model", "input": [{"role": "user", "content": [
                        {"type": "input_image", "image_url": "data:image/png;base64," + base64.b64encode(png(metadata)).decode()},
                    ]}]}
                    body = json.dumps(attachment).encode()
                    before = len(upstream.requests)
                    status, _, _ = call(base + "/v1/responses", body, timeout=185)
                    assert status == 200, "native image inspection/redaction failed"
                    forwarded = upstream.requests[before][2]
                    if metadata:
                        encoded = json.loads(forwarded)["input"][0]["content"][0]["image_url"].split(",", 1)[1]
                        assert TOKEN.encode() not in base64.b64decode(encoded), "image metadata secret survived"
                    else:
                        assert forwarded == body

                for metadata in (None, TOKEN):
                    attachment = {"model": "smoke-model", "input": [{"role": "user", "content": [
                        {"type": "input_file", "filename": "document.pdf", "file_data":
                         "data:application/pdf;base64," + base64.b64encode(pdf(metadata)).decode()},
                    ]}]}
                    body = json.dumps(attachment).encode()
                    before = len(upstream.requests)
                    status, _, _ = call(base + "/v1/responses", body, timeout=185)
                    assert status == 200, "native PDF inspection/redaction failed"
                    forwarded = upstream.requests[before][2]
                    if metadata:
                        encoded = json.loads(forwarded)["input"][0]["content"][0]["file_data"].split(",", 1)[1]
                        assert TOKEN.encode() not in base64.b64decode(encoded), "PDF metadata secret survived"
                    else:
                        assert forwarded == body

                # Invalid encoded image data must fail closed before the upstream.
                malformed = {"model": "smoke-model", "messages": [{"role": "user", "content": [
                    {"type": "image_url", "image_url": {"url": "data:image/png;base64,not-base64!!"}},
                ]}]}
                before = len(upstream.requests)
                status, _, _ = call(base + "/v1/chat/completions", json.dumps(malformed).encode(),
                                    {"Content-Type": "application/json"})
                assert status == 422 and len(upstream.requests) == before

                # Model discovery is forwarded too.
                status, _, models = call(base + "/v1/models", method="GET")
                assert status == 200 and b"smoke-model" in models
                assert upstream.requests[-1][0] == "/v1/models"

                # A stopped upstream cannot trigger direct/provider fallback.
                upstream.shutdown()
                upstream.server_close()
                before = len(upstream.requests)
                status, _, _ = call(base + "/v1/chat/completions", clean,
                                    {"Content-Type": "application/json"})
                assert status == 502 and len(upstream.requests) == before
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        logs = log_path.read_text(encoding="utf-8", errors="replace")
        assert TOKEN not in logs and CLIENT_KEY not in logs, "synthetic credential appeared in Preflight logs"
    upstream.server_close()
    print("PASS: real Preflight auth, clean Responses/Chat bytes and SSE, nested PAT redaction, sandboxed PNG/PDF inspection/redaction, attachment rejection, models, and upstream-down failure")


if __name__ == "__main__":
    main()
