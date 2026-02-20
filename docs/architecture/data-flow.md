# Data Flow

This page describes how data moves through the platform for the three main flows: telemetry, OTA updates, and remote access.

---

## 1. Telemetry Flow

```mermaid
graph LR
    subgraph device[Device]
        TEL[Telegraf]
        MQC[MQTT client]
    end
    TEL -->|"HTTP · CPU/RAM/disk/net metrics"| IDB[InfluxDB]
    IDB --> GRF[Grafana dashboards]
    MQC -->|"MQTTS · device state, alarms, OTA status"| TB[ThingsBoard]
    TB --> RE[Rule Engine]
    RE --> ALM["Alarms / Notifications"]
```

**Why two paths?**

- **ThingsBoard MQTT** handles business-logic telemetry (low frequency, device state changes, alarm conditions). ThingsBoard's rule engine can trigger actions based on this data.
- **Telegraf → InfluxDB** handles high-frequency performance metrics (sampled every 10 seconds or faster). This avoids overwhelming ThingsBoard's PostgreSQL backend.

### MQTT Message Format

ThingsBoard expects telemetry on topic `v1/devices/me/telemetry`:

```json
{
  "cpu_usage": 23.4,
  "mem_free_mb": 512,
  "sw_version": "1.0.0",
  "rauc_slot": "B",
  "ota_status": "idle"
}
```

---

## 2. OTA Update Flow

```mermaid
graph TD
    OP["Operator (hawkBit UI)<br/>creates Distribution Set + Rollout"]
    HB[hawkBit]
    UPD[rauc-hawkbit-updater]
    DL[downloads artefact]
    INST["rauc install (inactive slot)"]
    REBOOT[reboot into new slot]
    RPT[reports success]
    MQTT["MQTT publish → ThingsBoard<br/>sw_version · rauc_slot"]

    OP --> HB
    HB -->|"DDI poll (every 30 s)"| UPD
    UPD --> DL
    DL --> INST
    INST --> REBOOT
    REBOOT --> RPT
    RPT --> HB
    RPT --> MQTT
```

---

## 3. Remote Access Flow

```mermaid
graph TD
    BR["Browser (ThingsBoard UI)"]
    TXP["Terminal Proxy (Node.js)<br/>validates JWT · resolves WireGuard IP"]
    TTD["ttyd on device (ws://10.8.0.2:7681)"]
    SH["/bin/bash (PTY)"]

    BR -->|"WSS wss://terminal-proxy:8888/terminal?deviceId=…&token=JWT"| TXP
    TXP -->|"ws://10.8.0.2:7681 (via WireGuard VPN)"| TTD
    TTD --> SH
    SH -->|"keystrokes / output"| TTD
    TTD -->|"keystrokes / output"| TXP
    TXP -->|"keystrokes / output"| BR
```

---

## 4. Enrollment Flow (one-time)

```mermaid
sequenceDiagram
    participant D as Device bootstrap
    participant I as iot-bridge-api
    participant S as step-ca
    participant T as ThingsBoard

    D->>D: step crypto key pair → device.key
    D->>D: step certificate create → device.csr
    D->>I: POST /devices/{id}/enroll (CSR)
    I->>S: step-ca JWK provisioner issues OTT
    I->>S: POST /1.0/sign
    S-->>I: signed cert
    I->>I: allocate WireGuard IP (10.8.0.x)
    I-->>D: cert + CA chain + WireGuard config
    D->>D: save cert, apply WireGuard config
    D->>T: MQTT CONNECT (mTLS)
    T->>I: Rule Engine: POST_CONNECT webhook
    I->>I: create hawkBit target
    I->>I: record device metadata
```

---

## Network Diagram

```mermaid
graph TB
    subgraph browsers[Browsers]
        B1["Browser :8080"]
        B2["Browser :8180"]
        B3["Browser :3000"]
        B4["Browser :8090"]
        B5["Browser :8888"]
    end

    subgraph docker["Docker Internal Network 172.20.0.0/16"]
        TB[ThingsBoard]
        KC[Keycloak]
        GRF[Grafana]
        IDB[InfluxDB]
        HB[hawkBit]
        IBA[iot-bridge-api]
        TXP["terminal-proxy :8888"]
        SCA["step-ca :9000"]

        GRF --> IDB
    end

    subgraph wg["WireGuard VPN 10.8.0.0/24"]
        WGS["WireGuard server (10.8.0.1)"]
        DEV["Device (10.8.0.2)"]
        TLG[Telegraf]
        TTD["ttyd :7681"]
        UPD[rauc-hawkbit-updater]

        DEV --- TLG
        DEV --- TTD
        DEV --- UPD
    end

    B1 --> TB
    B2 --> KC
    B3 --> GRF
    B4 --> HB
    B5 --> TXP

    TLG -->|InfluxDB Line Protocol| IDB
    DEV -->|"UDP 51820"| WGS
    DEV -->|"MQTTS 8883"| TB
    WGS --> docker
    TXP --> TTD
```
