#!/usr/bin/env bash
# test.sh: smoke-test the wrapper. Requires the hello-world image to be
# pullable (or already local). Uses the wrapper default network
# (--network=host since 2026-11-10; --network=none fails on the
# current VM with crun ioctl SIOCSIFFLAGS, see README).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
./podman-sandbox run --rm docker.io/library/hello-world | grep -q "Hello from Docker"
echo "test OK: hello-world ran via podman-sandbox (default network)"
