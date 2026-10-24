#!/usr/bin/env bash
# build-image.sh: build factory-sandbox:latest from a Containerfile,
# reproducibly, without committing a demo container.
#
# Usage:
#   ./build-image.sh [factory-dir]
#   FACTORY_DIR=~/workspace/digital-product-factory ./build-image.sh
#
# The factory code is copied into an isolated .build context (gitignored),
# so the live factory is never touched and its code never enters this repo.
# Proxy and CA handling: if the host has proxy env vars and/or an egress
# CA bundle, they are passed as build args / a build volume. On a plain
# box without them, the build simply runs without those args.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# Use the wrapper on PATH, or the repo copy two levels up.
if ! command -v podman-sandbox >/dev/null 2>&1 && [ -x "$PWD/../../podman-sandbox" ]; then
  PATH="$PWD/../..:$PATH"
fi

FACTORY_DIR="${1:-${FACTORY_DIR:-$HOME/workspace/digital-product-factory}}"
BUILD_DIR="$PWD/.build"

if [ ! -f "$FACTORY_DIR/cli.py" ] || [ ! -d "$FACTORY_DIR/app" ]; then
  echo "build-image.sh: factory checkout not found at $FACTORY_DIR (need cli.py and app/)" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cp -r "$FACTORY_DIR/app" "$BUILD_DIR/app"
cp "$FACTORY_DIR/cli.py" "$FACTORY_DIR/requirements.txt" "$BUILD_DIR/"
cp "$PWD/Containerfile" "$BUILD_DIR/Containerfile"
find "$BUILD_DIR/app" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

BUILD_ARGS=()
for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
  if [ -n "${!var:-}" ]; then BUILD_ARGS+=(--build-arg "$var"); fi
done
VOLUME_ARGS=()
CA_FILE="/run/hatch/egress-tls/ca-bundle.pem"
if [ -f "$CA_FILE" ]; then
  VOLUME_ARGS=(-v "$CA_FILE:$CA_FILE:ro")
  BUILD_ARGS+=(--build-arg "PIP_CERT=$CA_FILE" --build-arg "SSL_CERT_FILE=$CA_FILE" --build-arg "REQUESTS_CA_BUNDLE=$CA_FILE")
fi

podman-sandbox build --network=host "${BUILD_ARGS[@]}" "${VOLUME_ARGS[@]}" \
  -t factory-sandbox:latest -f "$BUILD_DIR/Containerfile" "$BUILD_DIR"

echo "Built factory-sandbox:latest. Run the demo with ./run-demo.sh (it will use this image) or the API with ./run-api.sh"
