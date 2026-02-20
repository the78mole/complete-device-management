# Data Flow

This page describes how data moves through the platform for the three main flows: telemetry, OTA updates, and remote access.

---

## 1. Telemetry Flow

```
Device
  ├─[Telegraf]── CPU/RAM/disk/net metrics ──HTTP──► InfluxDB ──► Grafana dashboards
  └─[MQTT client]── device state, alarms, OTA status ──MQTTS──► ThingsBoard
                                                                    └── Rule Engine
                                                                          └── alarms, notifications
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

```
Operator (hawkBit UI)
  └── creates Distribution Set + Rollout
          │
          ▼
      hawkBit ──DDI poll (every 30s)──► Device rauc-hawkbit-updater
                                              │
                                         downloads artefact
                                              │
                                         rauc install (inactive slot)
                                              │
                                         reboot into new slot
                                              │
                                         reports success ──► hawkBit
                                              │
                                         MQTT publish ──► ThingsBoard (sw_version, rauc_slot)
```

---

## 3. Remote Access Flow

```
Browser (ThingsBoard UI)
  └── Terminal Widget opens WebSocket to:
        wss://terminal-proxy:8888/terminal?deviceId=device-001&token=<Keycloak JWT>
              │
        terminal-proxy validates JWT (Keycloak JWKS)
              │
        resolves device-001 → WireGuard IP (10.8.0.2)
              │
        proxies WebSocket to:
              http://10.8.0.2:7681 (ttyd on device via WireGuard VPN)
              │
        ttyd spawns /bin/bash in a PTY
              │
        keystrokes/output flow bidirectionally through the chain
```

---

## 4. Enrollment Flow (one-time)

```
Device bootstrap
  1. step crypto key pair → device.key (stays on device)
  2. step certificate create → device.csr
  3. POST /devices/{id}/enroll (CSR) → iot-bridge-api
        ├── step-ca JWK provisioner issues OTT
        ├── POST /1.0/sign → step-ca
        ├── allocates WireGuard IP (10.8.0.x)
        └── returns: cert + CA chain + WireGuard config
  4. Device saves cert, applies WireGuard config
  5. Device connects MQTT with mTLS
  6. ThingsBoard Rule Engine fires POST_CONNECT webhook → iot-bridge-api
        ├── creates hawkBit target
        └── records device metadata
```

---

## Network Diagram

```
                    ┌─────────────────────────────────────┐
                    │       Docker Internal Network        │
                    │        172.20.0.0/16                 │
                    │                                      │
  Browser  ─8080──► │ ThingsBoard ─────────────────────┐  │
  Browser  ─8180──► │ Keycloak                         │  │
  Browser  ─3000──► │ Grafana ◄── InfluxDB ◄──────────┐│  │
  Browser  ─8090──► │ hawkBit                         ││  │
                    │ iot-bridge-api                  ││  │
                    │ terminal-proxy ─8888──► Browser ││  │
                    │ step-ca ─9000                   ││  │
                    └─────────────────────────────────┼┼──┘
                                                      ││
                    ┌─────────────────────────────────┼┼──┐
                    │   WireGuard VPN 10.8.0.0/24     ││  │
                    │                                 ││  │
                    │ WireGuard server (10.8.0.1) ────┘│  │
                    │         │                        │  │
  Device ─UDP 51820─┤   Device (10.8.0.2)             │  │
          MQTTS 8883─┤    ├── Telegraf ────────────────┘  │
                    │    ├── ttyd :7681                    │
                    │    └── rauc-hawkbit-updater          │
                    └────────────────────────────────────  ┘
```
