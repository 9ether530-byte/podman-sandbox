# Example: Digital Download Factory inside Podman

The synergetic move: run a real business app — the Digital Download
Factory (FastAPI + 7-stage pipeline + reportlab PDFs) — inside the
podman-sandbox wrapper, isolated from the live factory.

## What this is not

This example does **not** copy the factory code into this repo. The
factory is a separate project. These scripts copy only `app/`,
`cli.py` and `requirements.txt` from a factory checkout into an
isolated `.workload/` directory here, and run everything there. The
live factory's `factory.db` and `outputs/` are never touched.

## Run it

```bash
./build-image.sh ~/workspace/digital-product-factory
# builds factory-sandbox:latest reproducibly from Containerfile
./run-demo.sh ~/workspace/digital-product-factory "Camping Meal Planner"
# outputs land in .workload/outputs; no container is committed
./run-api.sh
curl http://localhost:8001/health
podman-sandbox stop factory-api; podman-sandbox rm factory-api
```

`run-demo.sh` builds the image first if it does not exist yet.

## Verified live on 2026-10-24

- CLI demo for "Camping Meal Planner": 8 chapters, 10 PDF pages,
  QA 1.0, Gumroad $18.32 in simulated mode, PDF in outputs.
- Factory API from the built image (251 MB, replacing the earlier
  282 MB committed image) on port 8001: `/health` returned
  `digital-download-factory`, `/products` listed the
  container-generated product, `/niches/evaluate` matched live scoring.
- Live factory outputs and database were untouched (still Oct 19).

## Build note: cgroup manager

`podman build` RUN steps fail here with `crun: cannot open sd-bus`
unless the cgroup manager is cgroupfs. The wrapper now adds
`--cgroup-manager=cgroupfs` automatically for `build`, and
`build-image.sh` passes the proxy and egress CA bundle as build
args / a build volume when they exist, so pip works through the
proxy. On a plain box without them, the build runs without those args.

## Two limits this exposed

- Pip inside a container needs the host egress CA bundle mounted and
  passed through, or SSL verification fails through the proxy.
  `run-demo.sh` does that automatically when the bundle exists at
  `/run/hatch/egress-tls/ca-bundle.pem`, and skips it otherwise.
- Port 8000 is already taken by another service on the host network
  of the sandbox VM this was built on, so the API defaults to 8001.
  Host networking means port collisions are real; pick a free port
  with `PORT=8002 ./run-api.sh`.

## Safety

Do NOT publish from this container copy. The publisher runs in
simulated draft mode without keys, which is what was used here. Live
Gumroad publishing stays a separate step with the owner's keys.
