# GitHub Copilot Instructions – CDM Platform

This repository contains **Complete Device Management (CDM)**, a full-stack IoT platform
running as Docker Compose stacks.  Two main sub-stacks exist:

| Directory | Purpose |
|---|---|
| `cloud-infrastructure/` | All server-side services (Keycloak, ThingsBoard, Grafana, hawkBit, InfluxDB, MQTT broker, step-ca, RabbitMQ, nginx) |
| `device-stack/` | Edge-device simulation (bootstrap, MQTT telemetry, OTA updater, WireGuard VPN client) |
| `glue-services/` | Custom microservices: `iot-bridge-api` (FastAPI) and `terminal-proxy` (Node.js/TypeScript) |
| `docs/` | MkDocs documentation site |

## Key architectural facts

- **Entry point**: nginx on port **8888** (`cloud-infrastructure/nginx/nginx.conf`).
  All services are reachable via path-based routing EXCEPT ThingsBoard (port 9090 direct) and
  InfluxDB (port 8086 direct) due to SPA webpack absolute-path limitations.
- **Identity**: Keycloak 26.x at `/auth/` — see `.github/skills/cdm-keycloak/SKILL.md` for
  the full realm/user/client reference.
- **Proxy headers (GitHub Codespaces)**: nginx passes through `X-Forwarded-Host` from Codespaces
  unchanged via `map` directives so Keycloak builds correct external URLs.
- **Landing page**: `cloud-infrastructure/nginx/html/index.html` — Bootstrap dark theme,
  `buildPortUrl(port)` JS helper constructs Codespaces vs. localhost port URLs at runtime.
- **Environment variables**: `cloud-infrastructure/.env` (dev, git-ignored), modelled by
  `cloud-infrastructure/.env.example`.

## Service routing table

| Path / Port | Service | Notes |
|---|---|---|
| `/auth/` | Keycloak 8080 | OIDC, admin console |
| `/grafana/` | Grafana 3000 | `GF_SERVER_SERVE_FROM_SUB_PATH=true` |
| `/hawkbit/` | hawkBit 8070 | `SERVER_SERVLET_CONTEXT_PATH=/hawkbit` |
| `/api/` | IoT Bridge API 8000 | FastAPI, `ROOT_PATH=/api` |
| `/terminal/` | Terminal Proxy 8090 | WebSocket |
| `/rabbitmq/` | RabbitMQ Management 15672 | `management.path_prefix=/rabbitmq` |
| `/pki/` | step-ca 9000 | HTTPS upstream, `proxy_ssl_verify off` |
| `:9090` | ThingsBoard | Direct port (SPA, no sub-path proxy) |
| `:8086` | InfluxDB | Direct port (SPA, no sub-path proxy) |

## Conventions

- All Keycloak realm definitions live in `cloud-infrastructure/keycloak/realms/` as
  `realm-<name>.json.tpl`.  The entrypoint processes every `*.json.tpl` with `sed` and writes
  the rendered JSON to `/opt/keycloak/data/import/` before Keycloak starts with `--import-realm`.
- Passwords that must change in production are marked `# [CHANGE ME]` in `.env.example`.
- ThingsBoard OIDC uses a split URL pattern: browser-facing URLs use `EXTERNAL_URL` (goes
  through nginx), token/jwks endpoints use the internal Docker hostname `keycloak:8080`.

## Skill files

- **Keycloak**: `.github/skills/cdm-keycloak/SKILL.md`
