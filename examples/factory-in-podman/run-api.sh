#!/usr/bin/env bash
# run-api.sh: run the Digital Download Factory API from the
# factory-sandbox image (built by build-image.sh), on host networking.
#
# Port 8000 is already taken by another service on the sandbox VM this
# was built on, so the default port here is 8001. Override with:
#   PORT=8002 ./run-api.sh
#
# The API uses the isolated .workload directory created by run-demo.sh,
# never the live factory's database or outputs.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# Use the wrapper on PATH, or the repo copy two levels up.
if ! command -v podman-sandbox >/dev/null 2>&1 && [ -x "$PWD/../../podman-sandbox" ]; then
  PATH="$PWD/../..:$PATH"
fi

PORT="${PORT:-8001}"
WORKLOAD="$PWD/.workload"

if [ ! -d "$WORKLOAD/app" ]; then
  echo "run-api.sh: no .workload found. Run ./run-demo.sh first." >&2
  exit 1
fi
if ! podman-sandbox image exists factory-sandbox:latest >/dev/null 2>&1; then
  echo "run-api.sh: no factory-sandbox image found. Run ./build-image.sh first." >&2
  exit 1
fi

podman-sandbox rm -f factory-api >/dev/null 2>&1 || true
podman-sandbox run --network=host --name factory-api --workdir /code \
  -v "$WORKLOAD:/code" -d factory-sandbox \
  uvicorn app.main:app --host 0.0.0.0 --port "$PORT"

echo "Factory API running on http://localhost:$PORT/health"
echo "Stop it with: podman-sandbox stop factory-api; podman-sandbox rm factory-api"
