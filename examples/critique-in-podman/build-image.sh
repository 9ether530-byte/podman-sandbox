#!/usr/bin/env bash
# build-image.sh: build critique-sandbox:latest from a Containerfile.
#
# Usage:
#   ./build-image.sh [critique-dir]
#   CRITIQUE_DIR=~/workspace/critique-exchange ./build-image.sh
#
# The critique code is copied into an isolated .build context (gitignored),
# so the live critique checkout is never touched and its code never enters
# this repo. No keys are passed in.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# Use the wrapper on PATH, or the repo copy two levels up.
if ! command -v podman-sandbox >/dev/null 2>&1 && [ -x "$PWD/../../podman-sandbox" ]; then
  PATH="$PWD/../..:$PATH"
fi

CRITIQUE_DIR="${1:-${CRITIQUE_DIR:-$HOME/workspace/critique-exchange}}"
BUILD_DIR="$PWD/.build"

if [ ! -f "$CRITIQUE_DIR/requirements.txt" ] || [ ! -d "$CRITIQUE_DIR/app" ]; then
  echo "build-image.sh: critique checkout not found at $CRITIQUE_DIR (need requirements.txt and app/)" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cp -r "$CRITIQUE_DIR/app" "$BUILD_DIR/app"
cp "$CRITIQUE_DIR/requirements.txt" "$BUILD_DIR/"
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
  -t critique-sandbox:latest -f "$BUILD_DIR/Containerfile" "$BUILD_DIR"

echo "Built critique-sandbox:latest. Start the API with ./run-api.sh"
