# Architecture Overview

**Complete Device Management** is built around five integration pillars:

1. **Identity & Trust** — Keycloak (SSO, realm federation) + step-ca (PKI, two-tier CA hierarchy) establish who can connect and which certificates are trusted.
2. **Device Communication** — The Tenant-Stack ThingsBoard MQTT broker receives device telemetry and state; the central Provider-Stack RabbitMQ routes data via per-tenant vHosts.
3. **Software Updates** — hawkBit (Tenant-Stack) manages campaigns; RAUC executes them atomically on the device.
4. **Observability** — Device telemetry flows into the Tenant-Stack InfluxDB; platform-health metrics flow via RabbitMQ into the Provider-Stack InfluxDB.  Grafana is deployed in both stacks.
5. **Remote Access** — WireGuard (Tenant-Stack) creates a secure overlay network; ttyd + terminal-proxy deliver a browser shell.

For a complete picture of how the two stacks relate, see [Architecture → Stack Topology](stack-topology.md).

---

## High-Level Diagram

```mermaid
graph TB
    subgraph provider["Provider-Stack"]
        KC_P["Keycloak<br>(cdm + provider realms)"]
        RMQ["RabbitMQ<br>(central broker)"]
        IDB_P["InfluxDB<br>(platform metrics)"]
        GRF_P["Grafana<br>(platform dashboards)"]
        SCA_P["step-ca<br>(Root CA)"]
        IBA["IoT Bridge API"]
    end

    subgraph tenant["Tenant-Stack  ×N"]
        KC_T["Keycloak<br>(tenant realm)"]
        TB["ThingsBoard<br>(MQTT Broker + UI)"]
        HB["hawkBit<br>(OTA Campaigns)"]
        SCA_T["step-ca<br>(Sub-CA)"]
        WGS["WireGuard Server"]
        IDB_T["InfluxDB<br>(device telemetry)"]
        GRF_T["Grafana"]
        TXP["Terminal Proxy"]

        KC_T <-->|OIDC| TB
        TB <-->|REST| HB
        TB -->|Rule Engine| IDB_T
        IDB_T --> GRF_T
    end

    subgraph device["Edge Device"]
        BST["bootstrap"]
        WGC["wireguard-client"]
        MQC["mqtt-client"]
        TLG["telegraf"]
        RAU["rauc-updater"]
        TTD["ttyd"]
        BST --> WGC
        BST --> MQC
        BST --> TLG
        BST --> RAU
    end

    %% PKI chain
    SCA_P -->|"signs Sub-CA CSR"| SCA_T
    SCA_T -->|"issues device cert"| BST

    %% Keycloak federation
    KC_T -->|"Identity Provider federation"| KC_P

    %% Device connections
    MQC -->|"MQTTS mTLS (8883)"| TB
    WGC <-->|"WireGuard VPN"| WGS
    TLG -->|"MQTT / HTTP"| IDB_T
    RAU -->|"DDI poll"| HB
    TXP -->|"WS → WireGuard IP → ttyd"| TTD

    %% Tenant → Provider
    TB -.->|"metrics (AMQP)"| RMQ
    RMQ -->|"cdm-metrics vHost"| IDB_P
    IDB_P --> GRF_P

    %% Management
    IBA <-->|"tenant onboarding"| SCA_P
    IBA <-->|"vHost mgmt"| RMQ
    IBA <-->|"IdP registration"| KC_P
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

### Device Metrics Flow

```mermaid
sequenceDiagram
    participant D as Device (mqtt-client)
    participant T as ThingsBoard
    participant I as IoT Bridge API
    participant IDB as InfluxDB
    participant TEL as Cloud Telegraf
    participant HB as hawkBit
    D->>T: PUBLISH telemetry (MQTT TLS 8883)
    T->>I: Rule Engine: POST /webhooks/thingsboard/telemetry
    I->>I: extract tenant_id + device_id tags
    I->>IDB: write device_telemetry (line protocol)
    Note over I,IDB: tenant_id and device_id tags<br/>enforce multi-tenant isolation
    TEL->>HB: GET /rest/v1/targets (REST poll)
    HB-->>TEL: OTA target list (JSON)
    TEL->>IDB: write hawkbit_targets (line protocol)
```

---

## Data Segregation

| Data Type | Transport | Storage |
|---|---|---|
| Device state, alarms, OTA status | MQTT → ThingsBoard | ThingsBoard PostgreSQL |
| Device telemetry (CPU, RAM, disk, etc.) | MQTT → ThingsBoard Rule Engine → iot-bridge-api webhook → InfluxDB | InfluxDB |
| OTA / firmware-update status | Cloud Telegraf polls hawkBit REST API | InfluxDB |
| Optional sensor data | MQTT (`cdm/<tenant>/<device>/sensors`) → Telegraf → InfluxDB | InfluxDB |
| Audit / access logs | Keycloak events | Keycloak DB |

This design keeps ThingsBoard's database lean by offloading high-cardinality metric streams to InfluxDB. The three metric paths are:

- **Device telemetry**: ThingsBoard Rule Engine fires a webhook to the IoT Bridge API, which writes `device_telemetry` measurements tagged with `tenant_id` and `device_id` to enforce multi-tenant isolation.
- **OTA status**: Cloud Telegraf polls the hawkBit Management REST API and writes `hawkbit_targets` measurements to InfluxDB, giving operations teams a consolidated firmware rollout view.
- **Optional sensor data**: Devices may publish additional readings to the MQTT topic `cdm/<tenant>/<device>/sensors`; device-side or cloud-side Telegraf subscribes and writes them directly to InfluxDB.

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
