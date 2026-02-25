# Complete Device Management

**Complete Device Management** is an enterprise-grade, open-source **IoT Device & Software Lifecycle Management Platform** — a fully self-hosted alternative to commercial solutions such as Mender.io Enterprise.

It combines best-in-class open-source components into a cohesive, Zero-Trust platform that covers the entire device lifecycle:

- **Zero-Touch Provisioning** — devices enroll automatically using X.509 certificates signed by a private CA.
- **Secure OTA Updates** — Eclipse hawkBit manages software campaigns; RAUC executes A/B OS updates on the device.
- **Remote Troubleshooting** — WireGuard VPN + browser-based `ttyd` terminal embedded directly in the management UI.
- **High-Frequency Telemetry** — Telegraf streams metrics to InfluxDB; Grafana visualises them.
- **Single Sign-On** — Keycloak provides OIDC/SAML authentication across all services.
- **Multi-Tenancy** — each customer operates an independent Tenant-Stack; the Provider-Stack manages shared infrastructure and trust anchors.

---

## Platform Architecture

The platform is split into two independently deployable Compose stacks:

| Stack | Who operates it | Key services |
|---|---|---|
| **Provider-Stack** | CDM platform operator | Caddy, Keycloak (`cdm` + `provider` realms), RabbitMQ, InfluxDB, Grafana, step-ca Root CA, IoT Bridge API |
| **Tenant-Stack** *(Phase 2)* | Individual customer / tenant | Caddy, Keycloak (tenant realm), ThingsBoard, hawkBit, step-ca Sub-CA, WireGuard, Terminal Proxy, InfluxDB, Grafana |
| **Device-Stack** | Edge device (simulated) | bootstrap, mqtt-client, telegraf, rauc-updater, wireguard-client |

The Provider-Stack is the trust anchor for the entire platform: it hosts the Root CA, the central MQTT broker (RabbitMQ with one vHost per tenant), and the management API for tenant onboarding.

---

## Technology Stack

| Layer | Component | Role |
|---|---|---|
| IAM | Keycloak | OIDC/SAML SSO (Provider-Stack: `cdm`+`provider` realms; Tenant-Stack: per-tenant realm) |
| IoT Platform | ThingsBoard CE | Device registry, MQTT, Rule Engine, UI *(Tenant-Stack)* |
| OTA Backend | Eclipse hawkBit | Software campaign management *(Tenant-Stack)* |
| PKI | smallstep step-ca | Root CA + per-tenant Issuing Sub-CA; device & service cert signing |
| Time-Series DB | InfluxDB v2 | Provider metrics (Provider-Stack) + device telemetry (Tenant-Stack) |
| Visualisation | Grafana | Dashboards (both stacks) |
| Message Broker | RabbitMQ | Central MQTT broker with per-tenant vHosts *(Provider-Stack)* |
| Reverse Proxy | Caddy | Automatic HTTPS, path-based routing (replaces nginx) |
| VPN | WireGuard | Zero-trust device tunnel *(Tenant-Stack)* |
| Web Terminal | ttyd + Terminal Proxy | Secure browser shell *(Tenant-Stack)* |
| OTA Agent | RAUC + rauc-hawkbit-updater | A/B OS update execution |
| Metric Agent | Telegraf | Metric collection & forwarding |
| Glue Services | Python FastAPI + Node.js | Integration microservices |
| IaC | Docker Compose | Local eval + production deploy |

---

## Quick Navigation

<div class="grid cards" markdown>

- :material-download: **[Installation](installation/index.md)**  
  Set up the Provider-Stack, Tenant-Stack, or Device-Stack.

- :material-rocket-launch: **[Getting Started](getting-started/index.md)**  
  Start the Provider-Stack and enroll your first device in minutes.

- :material-sitemap: **[Architecture](architecture/index.md)**  
  Understand the two-stack topology, trust chains, and data flows.

- :material-cog-transfer: **[Workflows](workflows/device-provisioning.md)**  
  Detailed runbooks for provisioning, OTA, remote access, and monitoring.

- :material-lightbulb: **[Use Cases](use-cases/index.md)**  
  Real-world scenarios including tenant onboarding, fleet management, and incident response.

</div>

---

## Repository Structure

```
├── .github/
│   ├── workflows/          # CI + gh-pages deploy
│   ├── skills/             # Copilot skill files (Keycloak, …)
│   └── ISSUE_TEMPLATE/     # Bug & feature templates
├── provider-stack/         # Provider-side Compose stack (PKI, IAM, broker, management API)
├── cloud-infrastructure/   # Legacy monolithic stack (kept for reference; superseded by provider-stack)
├── glue-services/
│   ├── iot-bridge-api/     # FastAPI: PKI enrollment, tenant onboarding, WireGuard allocation
│   └── terminal-proxy/     # Node.js: JWT-validated WebSocket → ttyd proxy
├── device-stack/           # Edge device simulation (Docker Compose)
└── docs/                   # This documentation (MkDocs source)
```

---

## Licence

[MIT](https://github.com/the78mole/complete-device-management/blob/main/LICENSE) © the78mole contributors

---

## Technology Stack

| Layer | Component | Role |
|---|---|---|
| IAM | Keycloak | OIDC/SAML SSO |
| IoT Platform | ThingsBoard CE | Device registry, MQTT, Rule Engine, UI |
| OTA Backend | Eclipse hawkBit | Software campaign management |
| PKI | smallstep step-ca | Root CA, device & service cert signing |
| Time-Series DB | InfluxDB v2 | High-frequency telemetry |
| Visualisation | Grafana | Dashboards |
| VPN | WireGuard | Zero-trust device tunnel |
| Web Terminal | ttyd + Terminal Proxy | Secure browser shell |
| OTA Agent | RAUC + rauc-hawkbit-updater | A/B OS update execution |
| Metric Agent | Telegraf | Metric collection & forwarding |
| Glue Services | Python FastAPI + Node.js | Integration microservices |
| IaC | Docker Compose + Helm | Local eval + production deploy |

---

## Quick Navigation

<div class="grid cards" markdown>

- :material-download: **[Installation](installation/index.md)**  
  Prerequisites and step-by-step setup for cloud infrastructure and edge devices.

- :material-rocket-launch: **[Getting Started](getting-started/index.md)**  
  Enroll your first device and trigger your first OTA update in minutes.

- :material-sitemap: **[Architecture](architecture/index.md)**  
  Understand how all components fit together, trust chains, and data flows.

- :material-cog-transfer: **[Workflows](workflows/device-provisioning.md)**  
  Detailed runbooks for provisioning, OTA, remote access, and monitoring.

- :material-lightbulb: **[Use Cases](use-cases/index.md)**  
  Real-world scenarios including fleet management and incident response.

</div>

---

## Repository Structure

```
├── .github/
│   ├── workflows/          # CI + gh-pages deploy
│   └── ISSUE_TEMPLATE/     # Bug & feature templates
├── provider-stack/         # Provider-side Compose stack (PKI, IAM, broker, management API)
├── tenant-stack/           # Tenant-side Compose stack (ThingsBoard, hawkBit, WireGuard, ...)
├── cloud-infrastructure/   # Legacy monolithic stack – superseded; kept for reference
├── glue-services/
│   ├── iot-bridge-api/     # FastAPI: PKI enrollment, TB webhook, WireGuard allocation
│   └── terminal-proxy/     # Node.js: JWT-validated WebSocket → ttyd proxy
├── device-stack/           # Edge device simulation (Docker Compose)
└── docs/                   # This documentation (MkDocs/Zensical source)
```

---

## Licence

[MIT](https://github.com/the78mole/complete-device-management/blob/main/LICENSE) © the78mole contributors
