# Architecture Overview

**Complete Device Management** is built around five integration pillars:

1. **Identity & Trust** — Keycloak (SSO) + step-ca (PKI) establish who can connect and which certificates are trusted.
2. **Device Communication** — ThingsBoard provides the MQTT broker and the single-pane-of-glass UI.
3. **Software Updates** — hawkBit manages campaigns; RAUC executes them atomically on the device.
4. **Observability** — InfluxDB stores high-frequency metrics; Grafana visualises them.
5. **Remote Access** — WireGuard creates a secure overlay network; ttyd + terminal-proxy deliver a browser shell.

---

## High-Level Diagram

```mermaid
graph TB
    subgraph cloud["Cloud Infrastructure"]
        KC["Keycloak (IAM)"]
        TB["ThingsBoard (UI/MQTT Broker)"]
        HB["hawkBit (OTA Campaigns)"]
        SCA["step-ca (PKI)"]
        IBA["IoT Bridge API (FastAPI glue)"]
        WGS["WireGuard Server"]
        IDB[InfluxDB]
        TEL[Telegraf]
        GRF[Grafana]
        TXP["Terminal Proxy (WS + JWT)"]

        KC <-->|OIDC/SAML| TB
        TB <-->|REST| HB
        TB -->|"Rule Engine fires on device connect"| IBA
        SCA <-->|sign CSR| IBA
        IBA <-->|alloc peer| WGS
        TEL -->|metrics from device| IDB
        IDB --> GRF
    end

    subgraph device["Edge Device (Linux / Yocto / Docker simulation)"]
        BST["bootstrap (step-cli enroll)"]
        WGC[wireguard-client]
        MQC[mqtt-client]
        TLG[telegraf]
        RAU[rauc-updater]
        TTD[ttyd]

        BST --> WGC
        BST --> MQC
        BST --> TLG
        BST --> RAU
        BST --> TTD
    end

    MQC -->|"MQTT TLS (8883)"| TB
    WGC <-->|WireGuard VPN| WGS
    TLG -->|metrics| TEL
    TXP -->|"WS → WireGuard IP → ttyd"| TTD
```

---

## Component Interactions

### Enrollment Flow

```mermaid
sequenceDiagram
    participant D as Device
    participant I as IoT Bridge API
    participant S as step-ca
    D->>I: POST /devices/{id}/enroll (CSR)
    I->>S: sign CSR
    S-->>I: cert
    I->>I: create hawkBit target
    I->>I: allocate WireGuard IP
    I-->>D: cert + CA chain + WG config
```

### MQTT Connect Flow

```mermaid
sequenceDiagram
    participant D as Device
    participant T as ThingsBoard
    participant I as IoT Bridge API
    D->>T: MQTT CONNECT (mTLS)
    T->>I: Rule Engine: POST_CONNECT webhook
    I->>I: verify device exists
    I-->>T: 200 OK
    T-->>D: CONNACK
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

```mermaid
graph TB
    Internet["Internet (untrusted)"]
    RP["Reverse Proxy / Firewall<br/>expose only 443 · 8883 · 51820/udp"]

    subgraph mgmt["Management Network (docker internal)"]
        KC[Keycloak]
        TB[ThingsBoard]
        HB[hawkBit]
        GRF["Grafana (no direct internet exposure)"]
        IBA[iot-bridge-api]
        TXP[terminal-proxy]
    end

    subgraph vpn["Device VPN Network (10.8.0.0/24 WireGuard)"]
        WGS["WireGuard server (10.8.0.1)"]
        DEV["Devices (10.8.0.2 … 10.8.0.254)<br/>only reachable via VPN"]
    end

    Internet --> RP
    RP --> mgmt
    RP --> vpn
```
