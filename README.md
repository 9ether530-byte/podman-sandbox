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
| `netavark: setns: Operation not permitted` | Creating a network namespace is refused (effective caps here are essentially only `cap_sys_ptrace`, with no-new-privs) | `--network=host` (networked). Isolated bridge networking is **not** fixable from inside. `--network=none` also stopped working on the replacement VM in place from 2026-11-10 (see below) |
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

## On a normal Ubuntu box (not a restricted sandbox)

Run `./check.sh` first. If it reports `/dev/fuse` present and
isolated bridge networking works there, stock Podman will work
fine on its own — this repo is not needed for that case. The
wrapper still works there (vfs is slower than overlay, and it
refuses bridge networking by design), so it is safe to use as a
portable fallback, but it is not a replacement for stock Podman
where the normal modes already work. The guard snippet is for
restricted sandboxes that wipe Podman on VM replacement, not for
normal servers.

## Tested on

Ubuntu 24.04, Podman 4.9.3, 2026-10-24: hello-world with
`--network=none`, Alpine with `--network=host`, a full
remove-then-reinstall cycle through `install.sh`, the factory
demo and API from a Containerfile build, and `prune.sh` /
`check.sh` reporting.

Re-audited 2026-11-10 on a replacement VM (4 cores, 7.7 GiB RAM,
150G disk; caps now include `cap_net_admin` and `cap_net_raw`):
bridge networking is still blocked (netavark setns refused) and
the wrapper is still required. The first workload, factory demo,
and critique capture loop were all re-verified live that day.
Note: `check.sh` / `prune.sh` no longer run an unbounded
`du -sh` on the graphroot — it took over 60s on 155 vfs layers,
so it is bounded to 15s and skipped with a note when slow.

`--network=none` regression (2026-11-10): on the replacement VM,
every `--network=none` container fails with
`crun: ioctl(SIOCSIFFLAGS): Operation not permitted`, even with
`--cgroups=disabled` and even though the caps now include
`cap_net_admin`. It worked on the Oct 24 VM. This is a host-level
change, not fixable from inside — same class as fuse/netns. The
wrapper default is therefore `--network=host` until a future VM
makes none work again. Explicit `--network=none` is still passed
through (it will fail with the crun error, not a wrapper error),
so do not use it on this VM.

## Files

- `install.sh` — apt install (Ubuntu/Debian) if Podman is missing, plus
  the `/etc` config restore and an optional `/usr/local/bin` install of
  the wrapper. Safe to re-run.
- `podman-sandbox` — the wrapper. Passes vfs storage, a persistent data
  dir, and `--cgroups=disabled`; defaults `run`/`create` to
  `--network=host` (the only working mode on the VM in place from
  2026-11-10 — `--network=none` fails there with
  `crun: ioctl(SIOCSIFFLAGS): Operation not permitted`, so the old
  `--network=none` default was flipped to host on 2026-11-10; flip it
  back if a future VM makes none work again), and refuses bridge
  networking with a useful error instead of a netavark failure.
- `check.sh` — diagnostics: Podman version, `/dev/fuse`, capabilities,
  cgroup writability, storage driver, plus disk use (`podman system
  df` and graphroot size). No image pull.
- `test.sh` — smoke test: hello-world via the wrapper.
- `prune.sh` — safe disk reclaim: stopped containers and dangling
  images only. It deliberately does NOT run `image prune -a`,
  `system prune`, or `volume prune`, which would delete kept images
  or real data. Use `--dry-run` to preview. Measured 2026-10-24:
  prune reclaimed 0 bytes, because the cost here is vfs
  duplication (see Disk below), not dangling images.
- `PORTS.md` — the host-network port map. With `--network=host`,
  container ports are host ports, so this records what JARVIS, n8n,
  and the Podman workloads use or reserve, and the rule for picking
  a new one.
- `configs/storage.conf` — vfs template (`__DATA_DIR__` is substituted
  by `install.sh`); `configs/containers.conf` — cgroups disabled.
- `guard/HEARTBEAT.snippet.md` — one line to add to a heartbeat checklist
  so a periodic tick reinstalls Podman if a VM wipe removed it.
- `guard/IMAGES.snippet.md` — optional heartbeat line to report
  missing factory/critique images (rebuilding them is deliberate,
  not automatic, so this snippet only reports, it never rebuilds).
- `examples/first-workload/` — the first real workload verified with
  this wrapper: a stdlib-only Python service in `python:3.12-slim`,
  host-networked on port 8765, with a volume mount that writes its
  result back to the host. See its README for the run and the
  verified result.
- `examples/factory-in-podman/` — the synergetic workload: a
  Containerfile and `build-image.sh` that build the Digital
  Download Factory reproducibly, plus runner scripts for its CLI
  demo and API inside Podman, isolated from the live factory. The
  factory code itself is not in this repo; the scripts copy it to
  isolated `.build/` / `.workload/` directories. See its README
  for the verified run.
- `examples/critique-in-podman/` — the second business app in
  Podman: a Containerfile and `build-image.sh` for the Micro-SaaS
  Critique Exchange gateway, plus `run-api.sh`. No keys are passed
  in, so escrow is in mock mode and Stripe is not configured.
  See its README for the verified run, and for a real `/trends`
  bug found in the critique source (not a container bug).

## Boot-guard

The heartbeat line in `guard/HEARTBEAT.snippet.md` checks
`podman --version` and that the graph driver is `vfs`. If either check
fails, it runs `install.sh` and verifies hello-world. Recovery is on the
heartbeat cadence (about 30 minutes on the VM this was built on), not
instant, and it restores Podman in its limited form — it cannot grant
fuse, a network namespace, or user namespaces.

## Disk: vfs duplication is the real cost

`podman system df` said 290.7 MB, but the graphroot on disk was
977 MB on 2026-10-24, and 3.3 GB after the 994 MB critique image
was built the same day. vfs copies layers instead of sharing them,
and each committed image is a full filesystem copy (about 276 MB
for factory-sandbox, twice after two commits). `prune.sh` and
`podman rmi` on old/intermediate images did not shrink that
materially. So: do not commit repeatedly, build one image properly,
and only use `podman system reset` manually if disk really matters
— it deletes every image and container and forces re-pulls.

## What this does NOT solve

- Isolated container networking (bridge, pods with port publishing).
  Use host networking and mind port collisions, or run offline.
- GPU access, or resizing the host VM. Those are platform limits.
- Overlay performance: vfs copies layers instead of sharing them, so
  images use more disk. That is the price of working at all here.
