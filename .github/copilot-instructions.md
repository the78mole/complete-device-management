# GitHub Copilot Instructions – CDM Platform

This repository contains **Complete Device Management (CDM)**, a full-stack IoT platform
running as Docker Compose stacks.

| Directory | Purpose |
|---|---|
| `provider-stack/` | Central platform services (Keycloak, RabbitMQ, InfluxDB, Grafana, step-ca Root CA, IoT Bridge API, Caddy) |
| `tenant-stack/` | Per-tenant services (ThingsBoard, hawkBit, WireGuard, Terminal Proxy, Keycloak tenant realm, step-ca Sub-CA, InfluxDB, Grafana, IoT Bridge API, Caddy) |
| `device-stack/` | Edge-device simulation (bootstrap, MQTT telemetry, OTA updater, WireGuard VPN client) |
| `glue-services/` | Shared microservice source: `iot-bridge-api` (FastAPI) and `terminal-proxy` (Node.js/TypeScript) |
| `cloud-infrastructure/` | **Legacy** monolithic stack – kept for reference only; do NOT add new features here |
| `docs/` | Zensical documentation site (`zensical.toml` at repo root) |

## Key architectural facts

- **Two-stack model**: Provider-Stack (one, central) + Tenant-Stack (one per customer tenant).
  Each stack is fully independent; they communicate via MQTT/mTLS (RabbitMQ vHost per tenant)
  and the IoT Bridge API JOIN workflow.
- **Entry point (both stacks)**: **Caddy** on port **8888** (`*/caddy/Caddyfile`).
  All services reachable via path-based routing EXCEPT ThingsBoard (:9090 direct) and
  InfluxDB (:8086 direct) due to SPA webpack absolute-path limitations.
- **Identity (Provider-Stack)**: Keycloak 26.x at `/auth/`, realms `cdm` and `provider`.
  See `.github/skills/cdm-keycloak/SKILL.md` for full realm/user/client reference.
- **Identity (Tenant-Stack)**: Each Tenant-Stack runs its own Keycloak, realm `${TENANT_ID}`.
  Tenant realm registers as Identity Provider in Provider `cdm` realm via JOIN workflow.
- **PKI**: Provider-Stack = Root CA (`provider-step-ca`).
  Tenant-Stack = Issuing Sub-CA (`${TENANT_ID}-step-ca`), CSR signed by Provider Root CA.
- **Proxy headers (GitHub Codespaces)**: Caddy forwards `X-Forwarded-Host` and
  `X-Forwarded-Proto` unchanged so Keycloak builds correct external redirect URIs.
- **Landing pages**: `*/caddy/html/index.html` — Bootstrap dark theme, `buildPortUrl(port)`
  JS helper constructs Codespaces vs. localhost port URLs at runtime.
- **Environment variables**: `*/env` (dev, git-ignored), modelled by `*/.env.example`.
  Lines marked `# [CHANGE ME]` must be changed in production.
- **Container naming**: `provider-*` prefix in provider-stack; `${TENANT_ID}-*` prefix in
  tenant-stack (e.g. `tenant1-keycloak`, `tenant1-thingsboard`).

## Provider-Stack routing table

| Path / Port | Service | Notes |
|---|---|---|
| `/auth/` | Keycloak 8080 | OIDC, admin console |
| `/grafana/` | Grafana 3000 | `GF_SERVER_SERVE_FROM_SUB_PATH=true` |
| `/api/` | IoT Bridge API 8000 | FastAPI, strip prefix, `ROOT_PATH=/api` |
| `/rabbitmq/` | RabbitMQ Management 15672 | `management.path_prefix=/rabbitmq` |
| `/pki/` | step-ca 9000 | HTTPS upstream, `tls_insecure_skip_verify` |
| `:8086` | InfluxDB / oauth2-proxy | Direct port (SPA limitation) |

## Tenant-Stack routing table

| Path / Port | Service | Notes |
|---|---|---|
| `/auth/` | Keycloak 8080 | Tenant realm at `/auth/realms/${TENANT_ID}/` |
| `/grafana/` | Grafana 3000 | `GF_SERVER_SERVE_FROM_SUB_PATH=true` |
| `/api/` | IoT Bridge API 8000 | FastAPI, strip prefix, `ROOT_PATH=/api` |
| `/hawkbit/` | hawkBit 8070 | `SERVER_SERVLET_CONTEXT_PATH=/hawkbit` |
| `/pki/` | step-ca Sub-CA 9000 | HTTPS upstream, `tls_insecure_skip_verify` |
| `/terminal/` | Terminal Proxy 8090 | WebSocket, JWT validated against tenant Keycloak |
| `:9090` | ThingsBoard | Direct port (SPA limitation) |
| `:8086` | InfluxDB / oauth2-proxy | Direct port (SPA limitation) |
| `:8883` | ThingsBoard MQTT TLS | Direct, device connections |
| `:51820/udp` | WireGuard | Direct, device VPN |

## Conventions

- Keycloak realm templates: `*/keycloak/realms/realm-<name>.json.tpl`.
  `docker-entrypoint.sh` substitutes `${VAR}` placeholders with `sed` and writes
  rendered JSON to `/opt/keycloak/data/import/` before `--import-realm` starts.
- ThingsBoard OIDC uses a **split URL pattern**: `authorization_uri` / `redirect_uri` use
  `EXTERNAL_URL` (browser-facing), `token_uri` / `jwks_uri` use internal Docker hostname
  `keycloak:8080` (server-to-server).
- hawkBit's RabbitMQ is **internal only** (DMF event bus) — separate from Provider RabbitMQ.
- WireGuard VPN subnet **must be unique per tenant** — see `.env.example` comment
  (`WG_INTERNAL_SUBNET=10.8.<n>.0`).
- Documentation uses **Zensical** (`zensical.toml`). Never create or restore `mkdocs.yml`.

## Skill files

- **Keycloak**: `.github/skills/cdm-keycloak/SKILL.md`
- **RabbitMQ OAuth2/OIDC**: `.github/skills/cdm-rabbitmq/SKILL.md`
- **InfluxDB OAuth2-Proxy & Token Injection**: `.github/skills/cdm-influxdb-proxy/SKILL.md`
- **step-ca PKI (Root CA, Sub-CA, certificates)**: `.github/skills/cdm-step-ca/SKILL.md`
- **Zensical (docs)**: `.github/skills/zensical/SKILL.md`
