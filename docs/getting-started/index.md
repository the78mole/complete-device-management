# Quickstart

This guide gets you from zero to a running Provider-Stack in under 10 minutes.
Device enrollment and Tenant-Stack setup are covered in the follow-on pages.

---

## What You Will Build

```mermaid
graph LR
    PS[\"Provider-Stack\nCaddy · Keycloak · RabbitMQ\nInfluxDB · Grafana · step-ca\"]
    TS[\"Tenant-Stack (Phase 2)\nThingsBoard · hawkBit\nWireGuard · Terminal Proxy\"]
    DS[\"Device-Stack\nmqtt-client · telegraf\nrauc-updater · wireguard-client\"]

    PS -- &quot;JOIN workflow&quot; --> TS
    TS -- &quot;enroll + connect&quot; --> DS
```

---

## Step 1 — Start the Provider-Stack

```bash
git clone https://github.com/the78mole/complete-device-management.git
cd complete-device-management/provider-stack
cp .env.example .env
# Edit .env — set all *_PASSWORD and STEP_CA_* values
docker compose up -d
docker compose ps   # wait until all services are healthy
```

Full details: [Provider-Stack Setup](../installation/provider-stack.md)

---

## Step 2 — Verify Core Services

```bash
# Keycloak admin console
open http://localhost:8888/auth/

# Grafana
open http://localhost:8888/grafana/

# IoT Bridge API docs
open http://localhost:8888/api/docs
```

---

## Step 3 — Enroll a Tenant *(Phase 2)*

The Tenant-Stack (ThingsBoard, hawkBit, WireGuard) is deployed per customer in Phase 2 via
the JOIN workflow.

\u2192 See [Tenant-Stack Setup](../installation/tenant-stack.md) and [Tenant Onboarding](../use-cases/tenant-onboarding.md).

---

## Step 4 — Enroll Your First Device *(requires Tenant-Stack)*

```bash
cd complete-device-management/device-stack
cp .env.example .env
# Edit .env — DEVICE_ID=device-001, point TENANT_API_URL to your Tenant-Stack
docker compose up
```

Watch the `bootstrap` container log:

```
[enroll] Generating EC P-256 key pair...
[enroll] Generating CSR for device-001...
[enroll] Sending CSR to Tenant IoT Bridge API...
[enroll] Certificate received — saving to /certs/device.crt
[enroll] WireGuard config saved to /certs/wg0.conf
[enroll] Done. Exiting cleanly.
```

All other device containers start automatically once enrollment succeeds.

---

## Next Steps

- [Provider-Stack Setup (detailed)](../installation/provider-stack.md) — all configuration options.
- [Enroll Your First Device (detailed)](first-device.md) — understand every step of the enrollment flow.
- [Trigger Your First OTA Update](first-ota-update.md) — deploy a firmware bundle via hawkBit.
- [Remote Access](../workflows/remote-access.md) — open a browser terminal on your device.

