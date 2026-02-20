# Quickstart

This guide gets you from zero to a working device enrolled in the platform, sending telemetry, in under 20 minutes.

---

## What You Will Build

```
step-ca (Root CA)
    └── signs device certificate
            └── device MQTT client  ──TLS──►  ThingsBoard  ──Rule Engine──►  iot-bridge-api
                                                                                    ├── hawkBit target created
                                                                                    └── WireGuard IP allocated
device Telegraf  ──────────────────────────────────────────────────────────────►  InfluxDB → Grafana
```

---

## Step 1 — Start the Cloud Stack

```bash
git clone https://github.com/the78mole/complete-device-management.git
cd complete-device-management/cloud-infrastructure
cp .env.example .env
# Edit .env — set all *_PASSWORD and STEP_CA_* values
docker compose up -d
docker compose ps   # wait until all services are healthy
```

Full details: [Cloud Infrastructure Setup](../installation/cloud-infrastructure.md)

---

## Step 2 — Bootstrap ThingsBoard

```bash
docker compose exec thingsboard bash /provision/provision.sh
```

---

## Step 3 — Enroll Your First Device

```bash
cd ../device-stack
cp .env.example .env
# Edit .env — set DEVICE_ID=device-001 and point URLs to your cloud host
docker compose up
```

Watch the `bootstrap` container log:

```
[enroll] Generating EC P-256 key pair...
[enroll] Generating CSR for device-001...
[enroll] Sending CSR to iot-bridge-api...
[enroll] Certificate received — saving to /certs/device.crt
[enroll] WireGuard config saved to /certs/wg0.conf
[enroll] Done. Exiting cleanly.
```

All other services start automatically once enrollment succeeds.

---

## Step 4 — Verify in ThingsBoard

1. Open **http://localhost:8080** and log in.
2. Navigate to **Devices** — `device-001` should appear with status *Active*.
3. Open the device and check the **Latest Telemetry** tab — CPU, memory, and disk metrics arrive from Telegraf.

---

## Step 5 — View Metrics in Grafana

1. Open **http://localhost:3000** (admin / your password from `.env`).
2. Go to **Dashboards → Device Overview**.
3. Select `device-001` from the device dropdown.

---

## Next Steps

- [Enroll Your First Device (detailed)](first-device.md) — understand every step of the enrollment flow.
- [Trigger Your First OTA Update](first-ota-update.md) — upload a software bundle to hawkBit and deploy it.
- [Remote Access](../workflows/remote-access.md) — open a browser terminal on your device.
