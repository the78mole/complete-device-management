# Installation Overview

This page lists prerequisites and points you to the individual setup guides.

---

## Prerequisites

| Requirement | Minimum Version | Notes |
|---|---|---|
| Docker | 24.x | |
| Docker Compose | 2.20 | Ships with Docker Desktop |
| RAM (Provider-Stack) | 6 GB | 8 GB recommended |
| RAM (Tenant-Stack) | 8 GB | 16 GB recommended (ThingsBoard) |
| RAM (Device simulation) | 2 GB | |
| Disk (per stack) | 10 GB free | InfluxDB data grows over time |
| OS | Linux (amd64) | macOS works for development; Windows via WSL 2 |
| `git` | 2.40+ | |
| `step` CLI | 0.25+ | Required on the host only if you manage certs manually |

---

## Installation Paths

### Path A — Provider-Stack (start here)

The Provider-Stack is the trust anchor and central infrastructure for the platform.  Set it
up first before deploying any Tenant-Stacks.

→ [Provider-Stack Setup](provider-stack.md)

### Path B — Tenant-Stack *(Phase 2)*

Each customer tenant operates an independent Tenant-Stack.  It connects to the Provider-Stack
via the JOIN workflow after the Provider-Stack is running.

→ [Tenant-Stack Setup](tenant-stack.md)

### Path C — Device-Stack

Simulates an IoT edge device (bootstrap, MQTT telemetry, OTA updater, WireGuard client).  
Requires a running Tenant-Stack.

→ [Device-Stack Setup](device-stack.md)

!!! tip "GitHub Codespaces"
    Click the **Open in Codespaces** button in the README for a zero-install evaluation.
    Codespaces automatically builds images and forwards all required ports.  The
    `CODESPACE_NAME` URL scheme is handled transparently by Caddy and Keycloak.

---

## Port Map — Provider-Stack

| Service | Default Port/Path | Protocol |
|---|---|---|
| Caddy (entry point) | `:8888` | HTTP/HTTPS |
| Keycloak | `:8888/auth/` | HTTP |
| Grafana | `:8888/grafana/` | HTTP |
| IoT Bridge API | `:8888/api/` | HTTP |
| RabbitMQ Management | `:8888/rabbitmq/` | HTTP |
| InfluxDB | `:8086` | HTTP (direct) |
| step-ca | `:9000` | HTTPS (direct) |

## Port Map — Tenant-Stack *(planned)*

| Service | Default Port/Path | Protocol |
|---|---|---|
| Caddy (entry point) | `:8888` | HTTPS |
| Keycloak | `:8888/auth/` | HTTPS |
| ThingsBoard UI | `:9090` | HTTPS (direct) |
| ThingsBoard MQTT (mTLS) | `:8883` | MQTTS |
| hawkBit | `:8888/hawkbit/` | HTTPS |
| WireGuard | `:51820` | UDP |
| Terminal Proxy | `:8888/terminal/` | WSS |
| InfluxDB | `:8086` | HTTPS (direct) |
| step-ca | `:9000` | HTTPS (direct) |

!!! warning "Firewall"
    In production, only expose ports that must be reachable from the internet (WireGuard UDP,
    Caddy HTTPS `:443`, ThingsBoard MQTTS `:8883`).  All other ports should be behind the
    Caddy reverse proxy or restricted to the internal network.
