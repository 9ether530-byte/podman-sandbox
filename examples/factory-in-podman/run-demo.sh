#!/usr/bin/env bash
# run-demo.sh: run the Digital Download Factory's CLI demo inside Podman,
# isolated from the live factory.
#
# The factory code is NOT copied into this repo. This script copies only
# app/, cli.py and requirements.txt from a factory checkout into an
# isolated .workload directory next to this script, then runs the demo
# there. The live factory's factory.db and outputs/ are never touched.
#
# Usage:
#   ./run-demo.sh [factory-dir] [topic]
#   FACTORY_DIR=~/workspace/digital-product-factory ./run-demo.sh
#   ./run-demo.sh ~/workspace/digital-product-factory "Camping Meal Planner"
#
# The demo runs from factory-sandbox:latest, built reproducibly by
# ./build-image.sh. If that image does not exist yet, run-demo.sh
# builds it first instead of committing a demo container (each commit
# was a ~276 MB full copy under vfs).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# Use the wrapper on PATH, or the repo copy two levels up.
if ! command -v podman-sandbox >/dev/null 2>&1 && [ -x "$PWD/../../podman-sandbox" ]; then
  PATH="$PWD/../..:$PATH"
fi

FACTORY_DIR="${1:-${FACTORY_DIR:-$HOME/workspace/digital-product-factory}}"
TOPIC="${2:-Camping Meal Planner}"
WORKLOAD="$PWD/.workload"

if [ ! -f "$FACTORY_DIR/cli.py" ] || [ ! -d "$FACTORY_DIR/app" ]; then
  echo "run-demo.sh: factory checkout not found at $FACTORY_DIR (need cli.py and app/)" >&2
  exit 1
fi

mkdir -p "$WORKLOAD/outputs"
cp -r "$FACTORY_DIR/app" "$WORKLOAD/app"
cp "$FACTORY_DIR/cli.py" "$FACTORY_DIR/requirements.txt" "$WORKLOAD/"
find "$WORKLOAD/app" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

# Proxy and CA: pass through only what is set on the host. On the
# sandbox VM this was built on, pip inside a container fails on SSL
# verification unless the host egress CA bundle is mounted and passed
# through; on a plain box these steps are simply skipped.
PROXY_ARGS=()
for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY; do
  if [ -n "${!var:-}" ]; then PROXY_ARGS+=(-e "$var"); fi
done
CA_FILE="/run/hatch/egress-tls/ca-bundle.pem"
CA_ARGS=()
if [ -f "$CA_FILE" ]; then
  CA_ARGS=(-v "$CA_FILE:$CA_FILE:ro" -e SSL_CERT_FILE -e REQUESTS_CA_BUNDLE -e CURL_CA_BUNDLE -e "PIP_CERT=$CA_FILE")
fi

# If the built image does not exist yet, build it first.
if ! podman-sandbox image exists factory-sandbox:latest >/dev/null 2>&1; then
  echo "No factory-sandbox image yet; building it with ./build-image.sh ..."
  ./build-image.sh "$FACTORY_DIR"
fi

podman-sandbox rm -f factory-demo >/dev/null 2>&1 || true
podman-sandbox run --network=host --name factory-demo \
  -v "$WORKLOAD:/code" "${PROXY_ARGS[@]}" "${CA_ARGS[@]}" \
  factory-sandbox:latest bash -c "cd /code && python cli.py demo \"$TOPIC\" --output-dir outputs"

echo "Demo complete. Outputs in $WORKLOAD/outputs"
podman-sandbox rm factory-demo >/dev/null 2>&1 || true
echo "Done. Start the API with ./run-api.sh"
