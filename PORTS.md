# Port map — host networking means ports are shared

With `--network=host` there is no container port publishing: a
container that listens on a port listens on the host's port. Two
services on the same port collide, and the second one fails to bind
(this actually happened: the factory API first tried port 8000 and
the health check hit the JARVIS backend instead).

Rule: before starting a host-networked container, run `ss -ltn`,
pick a port that is not listed, and record it here. Stop the
container when you are done, so the port frees up again.

## Listening on 2026-10-24 (verified with `ss -ltnp`)

| Port | Service | Binding | Notes |
|---|---|---|---|
| 8000 | JARVIS/VISION backend (uvicorn) | 0.0.0.0 | DO NOT USE for containers. Systemd service `jarvis`. |
| 5678 | n8n | all interfaces | DO NOT USE. Systemd service `jarvis-n8n`. |
| 5679 | n8n (second listener) | 127.0.0.1 only | DO NOT USE. Same n8n process as 5678. |

## Reserved for Podman workloads (currently stopped, not listening)

| Port | Workload | Notes |
|---|---|---|
| 8001 | Digital Download Factory API in Podman | `examples/factory-in-podman/run-api.sh` defaults to this. |
| 8002 | Critique Exchange API in Podman | `examples/critique-in-podman/run-api.sh` defaults to this. |
| 8765 | First workload Python service | `examples/first-workload/`. |

## Suggested range for new container services

8001–8099, after checking `ss -ltn` first and adding the choice to
the table above. Never pick a port that is already listening, and
never assume a stopped workload's port is free forever — check each
time, because host services (JARVIS, n8n) restart on their own.
