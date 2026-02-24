# Use Cases Overview

This section describes real-world operational scenarios supported by **Complete Device Management**.

---

## Scenarios

| Use Case | Description |
|---|---|
| [Fleet Management](fleet-management.md) | Manage hundreds of devices across multiple tenants — provisioning, OTA rollouts, monitoring |
| [Security Incident Response](security-incident-response.md) | Revoke compromised certificates, isolate devices, audit access |
| [Troubleshooting](troubleshooting.md) | Diagnose and fix common operational issues |

---

## Typical Operator Day

A typical day for a fleet operator using this platform:

1. **Morning review** — open Grafana Fleet Summary dashboard; check for devices with high disk or CPU.
2. **Firmware rollout** — upload new RAUC bundle to hawkBit, create a staged rollout starting with 5% of the fleet.
3. **Remote debug** — use the ThingsBoard Terminal Widget to SSH into a device reporting errors.
4. **Alarm triage** — review ThingsBoard alarms; acknowledge resolved ones.
5. **Rollout approval** — after canary group succeeds (0 failures, 2 hours stable), expand to 100%.

---

## Multi-Tenant Operation

The platform is designed for multi-tenancy from the start:

- Each customer is a separate **Keycloak realm organisation** → mapped to a **ThingsBoard Tenant** → mapped to a **Grafana Organisation**.
- The `tenant-sync-service` in `iot-bridge-api` automates this mapping.
- Devices are isolated per tenant — operators of tenant A cannot see devices of tenant B.
- hawkBit supports tenant namespacing via the `X-Tenant-Id` header.

---

## Compliance & Audit

The platform generates audit trails at multiple levels:

| Source | What is logged | Retention |
|---|---|---|
| Keycloak | Login attempts, role changes, admin actions | Keycloak DB (export to SIEM) |
| ThingsBoard | Device connect/disconnect, telemetry ingestion | ThingsBoard DB |
| iot-bridge-api | Enrollment requests, webhook events | Application logs |
| step-ca | Certificate issuance, revocation | step-ca audit log |
| hawkBit | Deployment actions, artefact downloads | hawkBit DB |
