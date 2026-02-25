# Cloud Infrastructure Setup (Archiv)

!!! warning "Archiviert"
    Diese Installationsanleitung beschreibt den veralteten monolithischen Stack (`cloud-infrastructure/`).
    Er wurde durch [Provider-Stack](../installation/provider-stack.md) + [Tenant-Stack](../installation/tenant-stack.md) abgelöst.

This guide walks you through starting all cloud-side services using Docker Compose.

---

## 1. Clone the Repository

```bash
git clone https://github.com/the78mole/complete-device-management.git
cd complete-device-management/cloud-infrastructure
```

---

## 2. Configure Environment Variables

```bash
cp .env.example .env
```

Open `.env` and set every value marked `CHANGE_ME`. At a minimum:

| Variable | Description |
|---|---|
| `POSTGRES_PASSWORD` | Password for the shared PostgreSQL instance |
| `TB_DB_PASSWORD` | ThingsBoard's database password |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak bootstrap admin password |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password |
| `INFLUXDB_ADMIN_PASSWORD` | InfluxDB admin password |
| `INFLUXDB_ADMIN_TOKEN` | InfluxDB API token |
| `STEP_CA_PASSWORD` | step-ca key encryption password |
| `STEP_CA_PROVISIONER_PASSWORD` | Password for the JWK provisioner |

!!! danger "Secrets"
    Never commit your `.env` file. It is listed in `.gitignore`.

---

## 3. Start the Stack

```bash
docker compose up -d
```

Services start in dependency order. `step-ca` initialises first (generates Root CA and Intermediate CA), then all other services start.

Check that all containers are healthy:

```bash
docker compose ps
```

Expected output — every service should show `healthy` or `running`:

```
NAME              STATUS
step-ca           running (healthy)
postgres-kc       running (healthy)
keycloak          running (healthy)
postgres-tb       running (healthy)
thingsboard       running (healthy)
mysql-hawkbit     running (healthy)
hawkbit           running (healthy)
influxdb          running (healthy)
grafana           running (healthy)
wireguard         running
iot-bridge-api    running (healthy)
terminal-proxy    running (healthy)
```

---

## 4. Bootstrap ThingsBoard

After ThingsBoard is healthy, import the rule chain and create the X.509 device profile:

```bash
docker compose exec thingsboard bash /provision/provision.sh
```

This script:

1. Authenticates with ThingsBoard as the system administrator.
2. Imports `cloud-infrastructure/thingsboard/rule-chains/device-provisioning-chain.json`.
3. Creates a device profile named `cdm-x509` with X.509 mTLS authentication, bound to the imported rule chain.

---

## 5. Retrieve the step-ca Root CA Certificate

Devices and services need to trust the Root CA. Export it with:

```bash
docker compose exec step-ca step ca root /tmp/root_ca.crt
docker compose cp step-ca:/tmp/root_ca.crt ./root_ca.crt
```

Copy `root_ca.crt` to the device stack and to any client machine that needs to verify server certificates.

---

## 6. Configure Single Sign-On

Keycloak is pre-seeded with a `cdm` realm containing OIDC clients for ThingsBoard, hawkBit, and Grafana. The realm export is at `cloud-infrastructure/keycloak/realm-export.json`.

After first boot, update the client secrets in the Keycloak admin UI (http://localhost:8180) and copy them into your `.env`:

```
TB_KEYCLOAK_CLIENT_SECRET=<from Keycloak>
HAWKBIT_KEYCLOAK_CLIENT_SECRET=<from Keycloak>
GRAFANA_KEYCLOAK_CLIENT_SECRET=<from Keycloak>
```

Then restart the affected services:

```bash
docker compose restart thingsboard hawkbit grafana
```

---

## 7. Stopping the Stack

```bash
docker compose down          # stop containers, keep volumes
docker compose down -v       # stop containers AND delete all data (destructive)
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `step-ca` exits immediately | Missing `STEP_CA_PASSWORD` | Set it in `.env` |
| ThingsBoard not healthy after 3 min | DB not ready | `docker compose restart thingsboard` |
| hawkBit returns 401 | Keycloak client secret mismatch | Update `.env` → restart |
| `iot-bridge-api` returns 503 on enroll | step-ca not reachable | Check `STEP_CA_URL` in `.env` |
