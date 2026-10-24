#!/usr/bin/env bash
# prune.sh: reclaim Podman disk safely, without deleting kept images.
#
# What it does:
#   - removes stopped containers (container prune)
#   - removes dangling images only (image prune, no -a): these are
#     untagged layers left behind when an image tag moves, e.g. the
#     old factory-sandbox layer after a second commit
#
# What it deliberately does NOT do:
#   - `image prune -a` / `system prune`: those would delete every
#     unused image, including factory-sandbox and python:3.12-slim
#     that are kept intentionally for fast re-runs
#   - `volume prune`: volumes can hold real data; never prune them
#     blindly
#
# Honest limit, measured 2026-10-24: prune reclaimed 0 bytes here.
# The disk cost is vfs duplication, not dangling images. Each
# committed image is a full filesystem copy (about 276 MB for
# factory-sandbox), and `podman rmi` on the old image did not shrink
# the graphroot either (977 MB before and after). The real lever is
# behavioural: do not commit repeatedly, build one image properly
# (see the Containerfile step in the roadmap), and treat a full
# `podman system reset` — which deletes every image and container
# and forces re-pulls — as a manual, last-resort step only.
#
# Usage: ./prune.sh [--dry-run]
#   --dry-run prints what would be reclaimed without deleting anything.
set -u
# Use the wrapper on PATH, or the repo copy next to this script.
if command -v podman-sandbox >/dev/null 2>&1; then
  WRAPPER="podman-sandbox"
else
  WRAPPER="$(dirname "$0")/podman-sandbox"
fi
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; fi

DATA_DIR="${PODMAN_SANDBOX_DATA:-$HOME/workspace/podman-data}"
echo "before:"
"$WRAPPER" system df 2>&1 || true
if [ -d "$DATA_DIR/graphroot" ]; then
  echo "graphroot on disk: $(du -sh "$DATA_DIR/graphroot" 2>/dev/null | cut -f1)"
fi

if [ "$DRY_RUN" = 1 ]; then
  echo "dry-run: stopped containers and dangling images would be removed; nothing was deleted."
  exit 0
fi

"$WRAPPER" container prune -f 2>&1 || true
"$WRAPPER" image prune -f 2>&1 || true

echo "after:"
"$WRAPPER" system df 2>&1 || true
if [ -d "$DATA_DIR/graphroot" ]; then
  echo "graphroot on disk: $(du -sh "$DATA_DIR/graphroot" 2>/dev/null | cut -f1)"
fi
echo "kept images (should still include factory-sandbox and python):"
"$WRAPPER" images 2>&1 || true
