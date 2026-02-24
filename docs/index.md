# Complete Device Management

**Complete Device Management** is an enterprise-grade, open-source **IoT Device & Software Lifecycle Management Platform** — a fully self-hosted alternative to commercial solutions such as Mender.io Enterprise.

It combines best-in-class open-source components into a cohesive, Zero-Trust platform that covers the entire device lifecycle:

- **Zero-Touch Provisioning** — devices enroll automatically using X.509 certificates signed by a private CA.
- **Secure OTA Updates** — Eclipse hawkBit manages software campaigns; RAUC executes A/B OS updates on the device.
- **Remote Troubleshooting** — WireGuard VPN + browser-based `ttyd` terminal embedded directly in the management UI.
- **High-Frequency Telemetry** — Telegraf streams metrics to InfluxDB; Grafana visualises them.
- **Single Sign-On** — Keycloak provides OIDC/SAML authentication across all services.

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
├── cloud-infrastructure/   # All cloud-side service configs & Dockerfiles
├── glue-services/
│   ├── iot-bridge-api/     # FastAPI: PKI enrollment, TB webhook, WireGuard allocation
│   └── terminal-proxy/     # Node.js: JWT-validated WebSocket → ttyd proxy
├── device-stack/           # Edge device simulation (Docker Compose)
└── docs/                   # This documentation (MkDocs source)
```

---

## Licence

[MIT](https://github.com/the78mole/complete-device-management/blob/main/LICENSE) © the78mole contributors
