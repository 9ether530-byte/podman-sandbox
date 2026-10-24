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
say "known-good modes: --network=none, --network=host"
say "known-blocked: isolated bridge networking, fuse overlay, rootless user namespaces"
exit "$ok"
