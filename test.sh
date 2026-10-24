#!/usr/bin/env bash
# test.sh: smoke-test the wrapper. Requires the hello-world image to be
# pullable (or already local); network is disabled for the container itself.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
./podman-sandbox run --rm docker.io/library/hello-world | grep -q "Hello from Docker"
echo "test OK: hello-world ran via podman-sandbox with --network=none"
