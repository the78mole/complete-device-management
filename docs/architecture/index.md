# Architecture Overview

**Complete Device Management** is built around five integration pillars:

1. **Identity & Trust** — Keycloak (SSO) + step-ca (PKI) establish who can connect and which certificates are trusted.
2. **Device Communication** — ThingsBoard provides the MQTT broker and the single-pane-of-glass UI.
3. **Software Updates** — hawkBit manages campaigns; RAUC executes them atomically on the device.
4. **Observability** — InfluxDB stores high-frequency metrics; Grafana visualises them.
5. **Remote Access** — WireGuard creates a secure overlay network; ttyd + terminal-proxy deliver a browser shell.

---

## High-Level Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│  Cloud Infrastructure                                                            │
│                                                                                  │
│  ┌──────────┐  OIDC/SAML  ┌─────────────────┐  REST  ┌────────────────────┐    │
│  │ Keycloak │◄───────────►│   ThingsBoard    │◄──────►│     hawkBit        │    │
│  │  (IAM)   │             │  (UI/MQTT Broker)│        │  (OTA Campaigns)   │    │
│  └──────────┘             └────────┬─────────┘        └────────────────────┘    │
│                                    │ Rule Engine fires on device connect         │
│  ┌──────────┐             ┌────────▼─────────┐  alloc  ┌───────────────────┐   │
│  │ step-ca  │◄───────────►│  IoT Bridge API  │◄───────►│  WireGuard Server │   │
│  │  (PKI)   │  sign CSR   │  (FastAPI glue)  │  peer   └───────────────────┘   │
│  └──────────┘             └──────────────────┘                                  │
│                                                                                  │
│  ┌──────────┐             ┌──────────────────┐                                  │
│  │ InfluxDB │◄────────────│    Telegraf       │  (metrics from device)          │
│  └──────┬───┘             └──────────────────┘                                  │
│         │                                                                        │
│  ┌──────▼───┐             ┌──────────────────┐                                  │
│  │ Grafana  │             │ Terminal Proxy   │  WS + JWT validation             │
│  └──────────┘             └────────┬─────────┘                                  │
└────────────────────────────────────┼────────────────────────────────────────────┘
         ▲ MQTT TLS (8883)           │ WS → WireGuard IP → ttyd                   
         │                           │
┌────────┴───────────────────────────┴─────────────────────────────────────────┐
│  Edge Device (Linux / Yocto / Docker simulation)                              │
│                                                                                │
│  bootstrap (step-cli enroll)                                                  │
│      ↓                                                                         │
│  wireguard-client  ←→  mqtt-client  ←→  telegraf  ←→  rauc-updater  ←→  ttyd │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Interactions

### Enrollment Flow

```
Device                     IoT Bridge API              step-ca
  │─── POST /devices/{id}/enroll (CSR) ──►│                │
  │                                        │─── sign CSR ──►│
  │                                        │◄── cert ───────│
  │◄── cert + CA chain + WG config ────────│                │
  │                                        │── create hawkBit target
  │                                        │── allocate WireGuard IP
```

### MQTT Connect Flow

```
Device                       ThingsBoard                  IoT Bridge API
  │── MQTT CONNECT (mTLS) ──►│                                   │
  │                           │── Rule Engine: POST_CONNECT ─────►│
  │                           │              webhook              │── verify device exists
  │                           │◄────────────────── 200 OK ────────│
  │◄── CONNACK ───────────────│
```

---

## Data Segregation

| Data Type | Transport | Storage |
|---|---|---|
| Device state, alarms, OTA status | MQTT → ThingsBoard | ThingsBoard PostgreSQL |
| High-frequency metrics (CPU/RAM/disk) | Telegraf → InfluxDB directly | InfluxDB |
| Audit / access logs | Keycloak events | Keycloak DB |

This design keeps ThingsBoard's database lean by offloading high-cardinality metric streams to InfluxDB.

---

## Security Zones

```
Internet (untrusted)
    │
    ▼
[ Reverse Proxy / Firewall ]  ← expose only 443 (HTTPS), 8883 (MQTTS), 51820/udp (WireGuard)
    │
    ▼
Management Network (docker internal)
    ├── Keycloak
    ├── ThingsBoard
    ├── hawkBit
    ├── Grafana (no direct internet exposure — embedded via iframe)
    ├── iot-bridge-api
    └── terminal-proxy
    
Device VPN Network (10.8.0.0/24 WireGuard)
    ├── WireGuard server (10.8.0.1)
    └── Devices (10.8.0.2 ... 10.8.0.254) — only reachable via VPN
```
