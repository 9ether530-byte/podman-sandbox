# Example: first real workload

A stdlib-only Python service in `python:3.12-slim`, run via the
`podman-sandbox` wrapper. This is the workload verified live on
2026-10-24: it proves, beyond hello-world, a real runtime image, a
volume mount, host networking on port 8765, and real compute.

Run it from this directory:

```bash
podman-sandbox run --network=host --name first-workload \
  -v "$PWD:/work" \
  -d docker.io/library/python:3.12-slim python /work/app.py
curl http://localhost:8765/
cat output.json
podman-sandbox stop first-workload
podman-sandbox rm first-workload
```

Verified result on 2026-10-24: Python 3.12.15, sum of primes below
100,000 = 454396537, written back to `output.json` on the host via
the volume mount. Container stopped and removed afterwards; port 8765
closed. Known costs of this sandbox's workaround, also observed:
the image pull took ~44s, stopping needed SIGKILL after the 10s
SIGTERM timeout, and vfs disk use was already 426M after
hello-world + Alpine + Python.
