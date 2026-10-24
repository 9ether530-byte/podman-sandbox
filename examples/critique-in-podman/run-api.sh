#!/usr/bin/env bash
# run-api.sh: run the Critique Exchange API from the critique-sandbox
# image (built by build-image.sh), on host networking.
#
# Port 8002 is reserved for this in PORTS.md (8000 is the JARVIS
# backend, 8001 is the factory API). Override with:
#   PORT=8003 ./run-api.sh
#
# Data (SQLite DB, uploads, captures, packs) lives in an isolated
# .workload/data directory here, mounted at /code/data in the
# container. The live critique checkout's data/ is never touched.
# No keys are passed in: escrow is in mock mode, payouts return 503.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# Use the wrapper on PATH, or the repo copy two levels up.
if ! command -v podman-sandbox >/dev/null 2>&1 && [ -x "$PWD/../../podman-sandbox" ]; then
  PATH="$PWD/../..:$PATH"
fi

PORT="${PORT:-8002}"
WORKLOAD="$PWD/.workload"
mkdir -p "$WORKLOAD/data"

if ! podman-sandbox image exists critique-sandbox:latest >/dev/null 2>&1; then
  echo "run-api.sh: no critique-sandbox image found. Run ./build-image.sh first." >&2
  exit 1
fi

podman-sandbox rm -f critique-api >/dev/null 2>&1 || true
podman-sandbox run --network=host --name critique-api --workdir /code \
  -v "$WORKLOAD/data:/code/data" -e DATA_DIR=/code/data \
  -d critique-sandbox uvicorn app.main:app --host 0.0.0.0 --port "$PORT"

echo "Critique Exchange API running on http://localhost:$PORT/health"
echo "Stop it with: podman-sandbox stop critique-api; podman-sandbox rm critique-api"
