# Production-like Ubuntu install host

This image + `docker-compose.install.yml` give you an **Ubuntu 22.04** machine
with **systemd** and a **non-root `ubuntu` user that has passwordless sudo** —
closer to a VPS than the lightweight `docker compose` (dart:stable / root /
`AGENT_MODE=dev`) stack.

| | Dev compose (`docker-compose.yml`) | Install host (`docker-compose.install.yml`) |
|---|---|---|
| Base | `dart:stable` (Debian) | Ubuntu 22.04 |
| User | root | `ubuntu` + `sudo` |
| Init | Dart process | **systemd** |
| Agent | stubbed (`AGENT_MODE=dev`) | real (`infra/install.sh`) |
| `DOCKER_DEPLOY` | `true` | unset |

## Quick start

```bash
cd gisila-panel
./scripts/install-env.sh up
./scripts/install-env.sh install   # required — nothing listens until this runs
./scripts/install-env.sh check     # probe ports from outside the container
./scripts/install-env.sh shell     # interactive non-root shell
```

### Reachable from outside Docker (host / Windows)

| What | URL / command |
|------|----------------|
| Panel API | <http://localhost:8001> |
| Nginx | <http://localhost:18080> |
| SSH | `ssh -p 12222 ubuntu@localhost` (password `ubuntu`) |
| Postgres (panel DB) | `localhost:5456` |
| Redis | `localhost:6381` |

Until `./scripts/install-env.sh install` finishes, panel/nginx ports are published
but nothing is listening inside — browsers will fail to connect.

## Requirements

- Docker with privileged containers and host cgroup mount
- On WSL2: Docker Desktop or engine with cgroup v2; if systemd fails to start,
  check `docker logs gisila-install-host`

## Notes

- Postgres/Redis for this stack are separate from the dev stack (ports **5456** /
  **6381**) so both can run at once.
- Do **not** set `DOCKER_DEPLOY=true` here — Mongo/pgAdmin/agent paths need
  real `systemctl`.
- Production still prefers a real VPS; this is for local install/agent testing.
