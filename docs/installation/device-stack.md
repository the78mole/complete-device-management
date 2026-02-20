# Device Stack Setup

The device stack simulates a Linux IoT device using Docker Compose. It models the full edge lifecycle: PKI bootstrapping, WireGuard VPN, MQTT telemetry, OTA polling, and a web terminal.

---

## Prerequisites

- The [cloud infrastructure](cloud-infrastructure.md) must be running and healthy.
- The `root_ca.crt` exported from step-ca must be available (see the cloud setup guide).
- Docker and Docker Compose installed on the device (or simulation host).

---

## 1. Configure the Device Environment

```bash
cd device-stack
cp .env.example .env
```

Key variables to set:

| Variable | Description |
|---|---|
| `DEVICE_ID` | Unique identifier for this device (e.g. `device-001`) |
| `BRIDGE_API_URL` | URL of the `iot-bridge-api` (e.g. `http://192.168.1.10:8000`) |
| `STEP_CA_URL` | URL of step-ca (e.g. `https://192.168.1.10:9000`) |
| `STEP_CA_FINGERPRINT` | SHA-256 fingerprint of the Root CA — get it with `step certificate fingerprint root_ca.crt` |
| `TB_MQTT_HOST` | ThingsBoard MQTT host |
| `HAWKBIT_URL` | hawkBit server URL |
| `INFLUXDB_URL` | InfluxDB URL for Telegraf |
| `INFLUXDB_TOKEN` | InfluxDB write token |

---

## 2. Start the Device Stack

```bash
docker compose up
```

**Boot sequence:**

1. **bootstrap** (one-shot) — generates an EC P-256 private key, creates a CSR, calls `iot-bridge-api /devices/{id}/enroll`, saves the signed certificate, CA chain, and WireGuard config to the shared `device-certs` volume.
2. All other services start only after `bootstrap` completes successfully.
3. **wireguard-client** — applies the WireGuard config and establishes a tunnel to the cloud.
4. **mqtt-client** — publishes simulated telemetry to ThingsBoard using mTLS.
5. **telegraf** — streams CPU/memory/disk metrics to InfluxDB.
6. **rauc-hawkbit-updater** — polls hawkBit DDI API and simulates RAUC A/B updates.
7. **ttyd** — exposes a web terminal on the WireGuard VPN IP, accessible via the terminal-proxy.

---

## 3. Verify Enrollment

After the `bootstrap` container exits (code 0), check that the certificate was issued:

```bash
docker compose exec mqtt-client ls /certs/
# Expected: device.key  device.crt  ca-chain.crt  wg0.conf
```

Check the certificate details:

```bash
docker compose exec mqtt-client \
  openssl x509 -in /certs/device.crt -noout -subject -issuer -dates
```

---

## 4. Running on Real Hardware (Yocto / Linux)

On a real device, replace the Docker simulation with native services:

1. Install `step-cli` and run `enroll.sh` at first boot (e.g. via a systemd one-shot service).
2. Install `wireguard-tools` and apply the generated `wg0.conf`.
3. Install `telegraf` and deploy `device-stack/telegraf/telegraf.conf`.
4. Install `rauc` and `rauc-hawkbit-updater`; deploy `device-stack/updater/rauc-hawkbit-updater.conf`.
5. Install `ttyd` using `device-stack/terminal/setup.sh`.

Refer to `device-stack/rauc/system.conf` for the reference RAUC A/B slot configuration for a Yocto image.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `bootstrap` exits with code 1 | `BRIDGE_API_URL` unreachable | Verify the cloud stack is up; check URL in `.env` |
| `bootstrap` exits with code 1 | step-ca fingerprint mismatch | Re-run `step certificate fingerprint root_ca.crt` and update `STEP_CA_FINGERPRINT` |
| `mqtt-client` disconnects immediately | ThingsBoard not accepting mTLS | Verify the X.509 device profile and that the CA is trusted by ThingsBoard |
| `wireguard-client` stays in `waiting` | `bootstrap` did not write `wg0.conf` | Check `bootstrap` logs |
