# podman-sandbox

Run Podman inside a restricted sandbox where the defaults fail.

This started on a platform-allocated Linux VM (2 cores, no GPU, proxy
egress, periodic VM replacement) where a plain `podman run` fails three
different ways at once. The repo packages the workarounds that were
verified there, so a fresh box can go from zero to a working container
with one script, and stay working after a wipe with a boot-guard.

## The problems, and what solves each

| Symptom | Cause in a restricted sandbox | Fix in this repo |
|---|---|---|
| `fuse: device not found`, overlay mount fails | `/dev/fuse` does not exist; `modprobe fuse` fails, the module is not in `/lib/modules`, and the host kernel is not accessible | vfs storage driver (`configs/storage.conf`, or the wrapper's `--storage-driver=vfs`) |
| `crun: cannot open sd-bus` | No systemd user bus / cgroup delegation for the container runtime | `--cgroups=disabled` (`configs/containers.conf`) |
| `netavark: setns: Operation not permitted` | Creating a network namespace is refused (effective caps here are essentially only `cap_sys_ptrace`, with no-new-privs) | `--network=none` (offline) or `--network=host` (networked). Isolated bridge networking is **not** fixable from inside |
| Rootless + pasta/slirp still fails | `newuidmap: write to uid_map failed` — user namespaces are blocked | Not used. Rootful + host/none networking is the working path |
| Podman disappears after a VM replacement | The binary and `/etc/containers/*` live outside the persistent home directory | `install.sh` is idempotent and re-runnable; see Boot-guard below |
| `~/.config/containers/*.conf` seems ignored | Rootful Podman reads `/etc/containers/*.conf`, not the home config | `install.sh` copies the templates into `/etc` (when root); the wrapper passes the same settings as flags, so it works either way |

## Quickstart

```bash
git clone <this-repo>
cd podman-sandbox
./install.sh
./podman-sandbox run --rm docker.io/library/hello-world
```

Networked example (shares the host network stack, by design):

```bash
./podman-sandbox run --network=host --rm docker.io/library/alpine sh
```

## Files

- `install.sh` — apt install (Ubuntu/Debian) if Podman is missing, plus
  the `/etc` config restore and an optional `/usr/local/bin` install of
  the wrapper. Safe to re-run.
- `podman-sandbox` — the wrapper. Passes vfs storage, a persistent data
  dir, and `--cgroups=disabled`; defaults `run`/`create` to
  `--network=none` unless you pick `--network=host`, and refuses bridge
  networking with a useful error instead of a netavark failure.
- `check.sh` — diagnostics: Podman version, `/dev/fuse`, capabilities,
  cgroup writability, storage driver. No image pull.
- `test.sh` — smoke test: hello-world via the wrapper.
- `configs/storage.conf` — vfs template (`__DATA_DIR__` is substituted
  by `install.sh`); `configs/containers.conf` — cgroups disabled.
- `guard/HEARTBEAT.snippet.md` — one line to add to a heartbeat checklist
  so a periodic tick reinstalls Podman if a VM wipe removed it.

## Boot-guard

The heartbeat line in `guard/HEARTBEAT.snippet.md` checks
`podman --version` and that the graph driver is `vfs`. If either check
fails, it runs `install.sh` and verifies hello-world. Recovery is on the
heartbeat cadence (about 30 minutes on the VM this was built on), not
instant, and it restores Podman in its limited form — it cannot grant
fuse, a network namespace, or user namespaces.

## What this does NOT solve

- Isolated container networking (bridge, pods with port publishing).
  Use host networking and mind port collisions, or run offline.
- GPU access, or resizing the host VM. Those are platform limits.
- Overlay performance: vfs copies layers instead of sharing them, so
  images use more disk. That is the price of working at all here.

## Tested on

Ubuntu 24.04, Podman 4.9.3, 2026-10-24: hello-world with
`--network=none`, Alpine with `--network=host`, and a full
remove-then-reinstall cycle through `install.sh`.
