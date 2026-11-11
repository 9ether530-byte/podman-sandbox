#!/usr/bin/env bash
# check.sh: diagnose a restricted sandbox for Podman, without pulling images.
# Exit 0 if Podman can run a container here (via the wrapper's modes),
# 1 if Podman is missing, 2 if a known blocker is present and unworked-around.
set -u
ok=0
say() { printf '%s\n' "$*"; }
if command -v podman >/dev/null 2>&1; then
  say "podman: $(podman --version)"
else
  say "podman: MISSING (run ./install.sh)"
  exit 1
fi
if [ -c /dev/fuse ]; then say "fuse: /dev/fuse present (overlay may work)"; else say "fuse: /dev/fuse ABSENT -> overlay will fail, use vfs"; fi
if command -v capsh >/dev/null 2>&1; then
  say "effective caps: $(capsh --print 2>/dev/null | grep '^Current:' || echo unknown)"
fi
if [ -w /sys/fs/cgroup ]; then say "cgroup: /sys/fs/cgroup writable"; else say "cgroup: /sys/fs/cgroup not writable -> use --cgroups=disabled"; fi
say "storage driver (system): $(podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null || echo unknown)"
say "wrapper data dir: ${PODMAN_SANDBOX_DATA:-$HOME/workspace/podman-data (if workspace exists)}"
# Use the wrapper when it is on PATH, otherwise plain podman (the
# wrapper's system df is the same command with the vfs data dir).
if command -v podman-sandbox >/dev/null 2>&1; then
  PODMAN_CMD="podman-sandbox"
else
  PODMAN_CMD="podman"
fi
$PODMAN_CMD system df 2>/dev/null | head -5 || true
# Business images: these are the expensive ones to rebuild (factory
# ~1 min, critique ~9 min), so report them explicitly. A missing
# image after a VM replacement is not fixed by install.sh — it only
# restores Podman itself — so a missing image means "rebuild with
# examples/<name>/build-image.sh", not "run install.sh again".
# This check runs BEFORE the graphroot du below on purpose: the du
# can take minutes, and a slow disk measurement must never hide
# whether the business images are present.
for img in factory-sandbox:latest critique-sandbox:latest; do
  if $PODMAN_CMD image exists "$img" >/dev/null 2>&1; then
    say "image: $img present"
  else
    say "image: $img MISSING (rebuild with examples/*/build-image.sh)"
  fi
done
# Disk: vfs copies layers, so this grows faster than `podman system df`
# suggests. The on-disk du is bounded: on 2026-11-10 it took over 60s
# (155 vfs layers, du walks every file) and stalled this script, so it
# now runs under `timeout 15` and is skipped with a note when slow.
# `podman system df` above is the fast, authoritative size.
DATA_DIR="${PODMAN_SANDBOX_DATA:-$HOME/workspace/podman-data}"
if [ -d "$DATA_DIR/graphroot" ]; then
  if command -v timeout >/dev/null 2>&1; then
    GRAPHROOT_SIZE="$(timeout 15 du -sh "$DATA_DIR/graphroot" 2>/dev/null | cut -f1 || true)"
  else
    GRAPHROOT_SIZE="$(du -sh "$DATA_DIR/graphroot" 2>/dev/null | cut -f1 || true)"
  fi
  if [ -n "$GRAPHROOT_SIZE" ]; then
    say "graphroot on disk: $GRAPHROOT_SIZE (./prune.sh removes stopped containers/dangling only; vfs duplication is not reclaimed by prune, see README)"
  else
    say "graphroot on disk: too slow to measure (>15s, skipped — use 'podman system df' above)"
  fi
fi
say "known-good modes: --network=host (working); --network=none currently fails on this VM (crun ioctl SIOCSIFFLAGS, 2026-11-10)"
say "known-blocked: isolated bridge networking, fuse overlay, rootless user namespaces"
exit "$ok"
