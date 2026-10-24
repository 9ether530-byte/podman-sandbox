#!/usr/bin/env python3
"""First real Podman workload: a small stdlib-only Python service.

It proves, in one run, the things hello-world cannot:
  - a real language runtime image (python:3.12-slim, not a static binary)
  - a volume mount: /work is the host workload directory, and the service
    writes output.json back into it, so the host can read the result
  - host networking: the service binds port 8765 on the host network,
    because isolated bridge networking is blocked in this sandbox
  - real compute: it sums the primes below 100,000 and reports the result

Endpoints:
  GET /         JSON: service, python version, hostname, prime result
  GET /health   plain "ok"
"""
import json
import platform
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

WORK_DIR = Path("/work")


def sum_primes(limit: int) -> int:
    sieve = bytearray(b"\x01") * (limit + 1)
    sieve[0:2] = b"\x00\x00"
    for i in range(2, int(limit**0.5) + 1):
        if sieve[i]:
            step = i
            start = i * i
            sieve[start : limit + 1 : step] = b"\x00" * ((limit - start) // step + 1)
    return sum(i for i, is_prime in enumerate(sieve) if is_prime)


RESULT = sum_primes(100_000)
OUTPUT = {
    "service": "first-workload",
    "python": platform.python_version(),
    "hostname": socket.gethostname(),
    "primes_below_100000_sum": RESULT,
}
WORK_DIR.mkdir(parents=True, exist_ok=True)
(WORK_DIR / "output.json").write_text(json.dumps(OUTPUT, indent=2) + "\n")
print(f"wrote /work/output.json: {OUTPUT}", flush=True)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = b"ok"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
        else:
            body = json.dumps(OUTPUT, indent=2).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8765), Handler)
    print("listening on 0.0.0.0:8765", flush=True)
    server.serve_forever()
