# Complete Device Management

> An enterprise-grade, open-source **IoT Device & Software Lifecycle Management Platform** — a self-hosted alternative to Mender.io Enterprise.

[![CI](https://github.com/the78mole/complete-device-management/actions/workflows/ci.yml/badge.svg)](https://github.com/the78mole/complete-device-management/actions/workflows/ci.yml)
[![Docs](https://github.com/the78mole/complete-device-management/actions/workflows/docs.yml/badge.svg)](https://the78mole.github.io/complete-device-management/)
[![Python 3.11+](https://img.shields.io/badge/python-3.11%2B-blue?logo=python&logoColor=white)](https://www.python.org/)
[![Node 20+](https://img.shields.io/badge/node-20%2B-green?logo=nodedotjs&logoColor=white)](https://nodejs.org/)
[![Docker](https://img.shields.io/badge/docker-compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)

---

## What Is This?

**complete-device-management** is a monorepo that scaffolds and implements a complete IoT lifecycle management platform from scratch using only open-source components.

The platform is split into two independently deployable stacks:

- **Provider-Stack** — operated by the CDM platform team. Provides the trust anchor (Root CA, Keycloak `cdm` realm), central message broker (RabbitMQ) and platform-wide observability (InfluxDB, Grafana).
- **Tenant-Stack** *(Phase 2)* — one stack per customer. Provides device-facing services: ThingsBoard MQTT, hawkBit OTA, WireGuard VPN, Terminal Proxy, and tenant-scoped telemetry.

Key capabilities:

- **Zero-Touch Device Provisioning** — devices boot, generate a key pair, enroll against the Tenant step-ca Sub-CA, receive a signed mTLS certificate (chain to Provider Root CA), and are automatically registered in ThingsBoard and hawkBit.
- **Secure OTA Updates** — Eclipse hawkBit (Tenant-Stack) manages software campaigns; `rauc-hawkbit-updater` on devices executes RAUC A/B OS updates.
- **Remote Troubleshooting** — WireGuard VPN + `ttyd` web terminal, proxied securely through a JWT-validated WebSocket gateway embedded in the ThingsBoard UI (both in Tenant-Stack).
- **High-Frequency Telemetry** — Telegraf → Tenant InfluxDB pipeline bypasses ThingsBoard's DB for performance; aggregated metrics flow via RabbitMQ to Provider InfluxDB for fleet-wide dashboards.
- **Single Sign-On** — Keycloak realm federation links each Tenant Keycloak into the Provider `cdm` realm; one login across all services.
- **Private PKI** — Two-tier hierarchy: Provider Root CA → Provider Intermediate CA → Tenant Sub-CA → Device certificates.

---

## Architecture Overview

```mermaid
flowchart BT
    subgraph provider[Provider-Stack]
        KC[Keycloak IAM\ncdm + provider realms]
        SCA[step-ca Root CA]
        RMQ[RabbitMQ]
        IDB_P[InfluxDB]
        GRF_P[Grafana]
        IBA_P[IoT Bridge API]

        SCA <-->|Sign Sub-CA| IBA_P
        RMQ --> IDB_P --> GRF_P
    end

    subgraph tenant[Tenant-Stack  Phase 2]
        KC_T[Keycloak\ntenant realm]
        TB[ThingsBoard MQTT]
        HB[hawkBit OTA]
        SCA_T[step-ca Sub-CA]
        WGS[WireGuard Server]
        TXP[Terminal Proxy]
        IDB_T[InfluxDB]
        GRF_T[Grafana]

        KC_T -->|federation| KC
        TB -->|Rule Engine| IBA_T[IoT Bridge API]
        SCA_T <-->|Sign| IBA_T
        TB -->|AMQP| RMQ
    end

    subgraph edge[Edge Device]
        BST[Bootstrap enroll.sh]
        UPD[RAUC Updater]
        TLG[Telegraf]
        MQC[MQTT Client]
        TTD[ttyd]
        WGC[WireGuard Client]
    end

    MQC -->|MQTTS mTLS| TB
    UPD -->|DDI poll| HB
    TLG -->|InfluxDB HTTP| IDB_T
    TTD <-->|WebSocket WireGuard| TXP
    WGC <-->|WireGuard VPN| WGS
    BST -->|enroll CSR| IBA_T
```

---

## Technology Stack

| Layer | Component | Stack | Role |
|---|---|---|---|
| Reverse Proxy | [Caddy](https://caddyserver.com/) | Both | Automatic HTTPS, path-based routing, entry point `:8888` |
| IAM | [Keycloak](https://www.keycloak.org/) | Both | OIDC SSO; Provider: `cdm`+`provider` realms; Tenant: tenant realm |
| Message Broker | [RabbitMQ](https://www.rabbitmq.com/) | Provider | Central MQTT/AMQP broker, vHost per tenant |
| IoT Platform | [ThingsBoard CE](https://thingsboard.io/) | Tenant | Device registry, MQTT broker, Rule Engine, UI |
| OTA Backend | [Eclipse hawkBit](https://eclipse.dev/hawkbit/) | Tenant | Software campaign management |
| PKI | [smallstep step-ca](https://smallstep.com/docs/step-ca/) | Both | Provider: Root+ICA; Tenant: Sub-CA for device certs |
| Time-Series DB | [InfluxDB v2](https://www.influxdata.com/) | Both | Provider: platform metrics; Tenant: device telemetry |
| Visualization | [Grafana](https://grafana.com/) | Both | Fleet dashboards (Provider) + device dashboards (Tenant) |
| VPN | [WireGuard](https://www.wireguard.com/) | Tenant | Zero-trust device tunnel |
| Web Terminal | [ttyd](https://github.com/tsl0922/ttyd) + Terminal Proxy | Tenant | Secure browser-based shell |
| OTA Agent | [RAUC](https://rauc.io/) + rauc-hawkbit-updater | Device | A/B OS update execution |
| Telemetry | [Telegraf](https://www.influxdata.com/time-series-platform/telegraf/) | Device | Metric collection & forwarding |
| Glue Services | Python [FastAPI](https://fastapi.tiangolo.com/) + Node.js | Both | IoT Bridge API + Terminal Proxy |
| IaC | Docker Compose | Both | Local evaluation and production deployment |

---

## Repository Structure

```
├── .github/
│   ├── workflows/          # CI (tests, lint, docs build) + gh-pages deploy
│   ├── skills/             # Keycloak runbook scripts + SKILL.md
│   └── ISSUE_TEMPLATE/     # Bug report & feature request forms
├── provider-stack/         # Provider-Stack: Caddy, Keycloak, RabbitMQ, InfluxDB, Grafana, step-ca
│   ├── docker-compose.yml
│   ├── caddy/              # Caddyfile, landing page
│   ├── keycloak/           # Realm templates (cdm + provider), init scripts
│   ├── monitoring/         # InfluxDB init, Grafana provisioning
│   ├── rabbitmq/           # RabbitMQ config, vHost definitions
│   └── step-ca/            # Root CA + ICA Dockerfile, cert templates
├── cloud-infrastructure/   # Legacy monolithic stack (pre-Phase 1.5, kept for reference)
├── glue-services/
│   ├── iot-bridge-api/     # FastAPI: PKI enrollment, TB webhook, WireGuard alloc
│   └── terminal-proxy/     # Node.js/TS: JWT-validated WebSocket → ttyd proxy
├── device-stack/           # Edge device simulation
│   ├── docker-compose.yml
│   ├── bootstrap/          # enroll.sh — generates key, signs cert via Tenant Sub-CA
│   ├── mqtt-client/        # mTLS MQTT telemetry publisher
│   ├── updater/            # hawkBit DDI poller (simulates RAUC)
│   ├── telegraf/           # telegraf.conf
│   ├── wireguard-client/   # WireGuard client container
│   ├── rauc/               # Reference RAUC system.conf
│   └── terminal/           # ttyd setup script
└── docs/                   # MkDocs source → gh-pages
```

---

## Quick Start

### Prerequisites

- Docker ≥ 24 + Docker Compose ≥ 2.20
- `git`
- 6 GB RAM for the Provider-Stack (8 GB recommended)

### 1. Clone & Configure

```bash
git clone https://github.com/the78mole/complete-device-management.git
cd complete-device-management/provider-stack
cp .env.example .env
# Edit .env – set all *_PASSWORD and STEP_CA_* variables
```

### 2. Start the Provider-Stack

```bash
docker compose up -d
docker compose ps   # wait until all containers are healthy
```

This starts: Caddy, Keycloak + Postgres, RabbitMQ, InfluxDB, Grafana, step-ca (Root CA + ICA), IoT Bridge API.

### 3. Retrieve the Root CA Fingerprint

```bash
docker compose exec provider-step-ca step certificate fingerprint /home/step/certs/root_ca.crt
```

Save this value — the Device-Stack needs it for enrollment.

### 4. Simulate a Device *(requires Tenant-Stack)*

The Device-Stack enrolls against a Tenant step-ca Sub-CA.  Until the Tenant-Stack is
available (Phase 2), you can run the bootstrap in demo mode:

```bash
cd ../device-stack
cp .env.example .env
# Edit .env – DEVICE_ID=device-001, TENANT_API_URL=<tenant-iot-bridge-api>
docker compose up
```

The `bootstrap` container enrolls the device (generates key, signs cert via Tenant Sub-CA),
then all other services start automatically.

### 5. Access the Provider-Stack UIs

| Service | URL | Default Credentials |
|---|---|---|
| **Caddy entry point** | http://localhost:8888/ | — |
| Keycloak | http://localhost:8888/auth/admin/ | admin / from `.env` |
| Grafana | http://localhost:8888/grafana/ | admin / from `.env` |
| RabbitMQ Management | http://localhost:8888/rabbitmq/ | admin / from `.env` |
| IoT Bridge API docs | http://localhost:8888/api/docs | — |
| InfluxDB | http://localhost:8086/ | admin / from `.env` |
| step-ca | https://localhost:9000/health | — |

> **Codespaces:** Replace `http://localhost:8888` with `https://<codespace-name>-8888.app.github.dev`.

---

## Documentation

Full documentation is available at **[https://the78mole.github.io/complete-device-management/](https://the78mole.github.io/complete-device-management/)**.

Topics covered:
- [Installation](https://the78mole.github.io/complete-device-management/installation/)
- [Getting Started](https://the78mole.github.io/complete-device-management/getting-started/)
- [Architecture](https://the78mole.github.io/complete-device-management/architecture/)
- [Workflows](https://the78mole.github.io/complete-device-management/workflows/device-provisioning/)
- [Use Cases](https://the78mole.github.io/complete-device-management/use-cases/)

---

## Contributing

We welcome contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

---

## License

[MIT](LICENSE) © the78mole contributors
