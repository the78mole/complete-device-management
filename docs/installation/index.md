# Installation Overview

This page lists everything you need before running the platform and points you to the individual setup guides.

---

## Prerequisites

| Requirement | Minimum Version | Notes |
|---|---|---|
| Docker | 24.x | |
| Docker Compose | 2.20 | Ships with Docker Desktop |
| RAM (cloud stack) | 8 GB | 16 GB recommended |
| RAM (device simulation) | 2 GB | |
| Disk (cloud stack) | 20 GB free | InfluxDB data grows over time |
| OS | Linux (amd64) | macOS works for development; Windows via WSL 2 |
| `git` | 2.40+ | |
| `step` CLI | 0.25+ | Required on the host only if you manage certs manually |

---

## Installation Paths

### Option A — Local Evaluation (Docker Compose)

The fastest way to get started. All components run as containers on a single machine.

1. [Cloud Infrastructure setup](cloud-infrastructure.md) — bring up Keycloak, ThingsBoard, hawkBit, step-ca, InfluxDB, Grafana, WireGuard, and the glue services.
2. [Device Stack setup](device-stack.md) — run a simulated IoT device that enrolls, connects, and sends telemetry.

### Option B — Production (Kubernetes)

Kubernetes Helm charts are scaffolded under `cloud-infrastructure/helm/` (work in progress). Refer to individual component documentation for production hardening advice.

---

## Port Map

| Service | Default Port | Protocol |
|---|---|---|
| ThingsBoard UI | 8080 | HTTP |
| ThingsBoard MQTT (plain) | 1883 | MQTT |
| ThingsBoard MQTT (TLS/mTLS) | 8883 | MQTTS |
| Keycloak | 8180 | HTTP |
| hawkBit | 8090 | HTTP |
| InfluxDB | 8086 | HTTP |
| Grafana | 3000 | HTTP |
| step-ca | 9000 | HTTPS |
| iot-bridge-api | 8000 | HTTP |
| terminal-proxy | 8888 | HTTP / WS |
| WireGuard | 51820 | UDP |

!!! warning "Firewall"
    In production, only expose ports that must be reachable from the internet (e.g., WireGuard UDP and the ThingsBoard MQTT TLS port). All other ports should be behind a reverse proxy or restricted to the internal network.
