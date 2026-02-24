# Use Cases Overview

This section describes real-world operational scenarios supported by **Complete Device Management**.

---

## Scenarios

| Use Case | Description |
|---|---|
| [Tenant Onboarding](tenant-onboarding.md) | Register a new customer tenant and connect their Tenant-Stack to the Provider-Stack |
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

The platform uses a **two-stack architecture** for multi-tenancy:

- **Provider-Stack** — operated by the CDM platform team.  Hosts the trust anchor
  (Keycloak `cdm` realm, Root CA, RabbitMQ), collects platform-health metrics.
- **Tenant-Stack** — one stack per customer.  Hosts ThingsBoard, hawkBit, WireGuard,
  device telemetry InfluxDB, and a tenant-scoped Keycloak realm that federates into the
  Provider Keycloak.

The `iot-bridge-api` in each Tenant-Stack manages device enrollment and synchronises
device metadata with the Provider-Stack.  Devices are fully isolated — operators of
Tenant A cannot see devices of Tenant B.

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
