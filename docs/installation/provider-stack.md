# Provider-Stack Setup

This guide walks you through starting all provider-side services using Docker Compose.
The Provider-Stack is the **trust anchor** of the entire CDM platform: it hosts the Root CA,
the central MQTT broker, and the management API that tenant stacks register against.

!!! tip "GitHub Codespaces"
    The fastest way to evaluate the platform is via the **Open in Codespaces** button in
    the repository README.  Codespaces automatically forwards all required ports through
    the `CODESPACE_NAME` URL scheme.  All scripts default to `http://localhost:8888`; in
    Codespaces replace that with the forwarded URL shown in the **Ports** tab.

---

## Prerequisites

| Requirement | Minimum Version | Notes |
|---|---|---|
| Docker | 24.x | |
| Docker Compose | 2.20 | Ships with Docker Desktop |
| RAM | 6 GB | 8 GB recommended |
| Disk | 10 GB free | InfluxDB data grows over time |
| OS | Linux (amd64) | macOS works for development; Windows via WSL 2 |
| `git` | 2.40+ | |
| `step` CLI | 0.25+ | Required on the host only if you manage certs manually |

---

## 1. Clone the Repository

```bash
git clone https://github.com/the78mole/complete-device-management.git
cd complete-device-management/provider-stack
```

---

## 2. Configure Environment Variables

```bash
cp .env.example .env
```

Open `.env` and set every value marked `# [CHANGE ME]`.  At a minimum:

| Variable | Description |
|---|---|
| `EXTERNAL_URL` | Browser-facing base URL (e.g. `http://localhost:8888`). **In GitHub Codespaces** set to the full forwarded URL: `https://<CODESPACE_NAME>-8888.app.github.dev` |
| `INFLUX_EXTERNAL_URL` | Browser-facing URL for the InfluxDB port. **In GitHub Codespaces:** `https://<CODESPACE_NAME>-8086.app.github.dev` |
| `POSTGRES_PASSWORD` | Password for the Keycloak PostgreSQL instance |
| `KC_ADMIN_USER` | Keycloak bootstrap admin username (default: `admin`) |
| `KC_ADMIN_PASSWORD` | Keycloak bootstrap admin password |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password |
| `INFLUXDB_ADMIN_PASSWORD` | InfluxDB admin password |
| `INFLUXDB_ADMIN_TOKEN` | InfluxDB API token — also used by `influxdb-token-injector` for transparent backend auth |
| `STEP_CA_PASSWORD` | step-ca Root CA key encryption password |
| `STEP_CA_PROVISIONER_PASSWORD` | Password for the JWK provisioner |
| `GRAFANA_OIDC_SECRET` | Grafana OIDC client secret (set after first Keycloak boot) |
| `BRIDGE_OIDC_SECRET` | IoT Bridge API OIDC client secret |
| `INFLUXDB_PROXY_OIDC_SECRET` | InfluxDB oauth2-proxy OIDC client secret — copy from the `influxdb-proxy` client in the **`cdm`** realm after first Keycloak boot |
| `PROVIDER_OPERATOR_PASSWORD` | Initial password for `provider-operator` user |
| `RABBITMQ_ADMIN_PASSWORD` | RabbitMQ admin password (local fallback; SSO is preferred) |
| `RABBITMQ_MANAGEMENT_OIDC_SECRET` | RabbitMQ Management OIDC client secret — copy from the `rabbitmq-management` client in the **`provider`** realm after first Keycloak boot |
| `INFLUX_PROXY_COOKIE_SECURE` | `false` (localhost) / `true` (HTTPS/Codespaces) — controls the `Secure` flag on oauth2-proxy session cookies |
| `INFLUX_PROXY_COOKIE_SAMESITE` | `lax` (localhost) / `none` (HTTPS/Codespaces) — must be `none` for cross-origin Codespaces redirects |

!!! tip "GitHub Codespaces"
    When running in Codespaces, `EXTERNAL_URL` and `INFLUX_EXTERNAL_URL` **must** be set to
    the Codespaces-forwarded URLs (`*.app.github.dev`).  Using `localhost` causes `oauth2-proxy`
    to reject redirects and Keycloak to generate broken asset URLs.  Also set
    `INFLUX_PROXY_COOKIE_SECURE=true` and `INFLUX_PROXY_COOKIE_SAMESITE=none`.

!!! danger "Secrets"
    Never commit your `.env` file.  It is listed in `.gitignore`.

---

## 3. Start the Stack

```bash
docker compose up -d
```

Services start in dependency order.  `step-ca` initialises first (generates Root CA and
Intermediate CA on first boot), then the remaining services start.

Check that all containers are running:

```bash
docker compose ps
```

Expected output — every service should show `healthy` or `running`:

```
NAME                                STATUS
provider-step-ca                    running (healthy)
provider-keycloak-db                running (healthy)
provider-keycloak                   running (healthy)
provider-rabbitmq                   running (healthy)
provider-influxdb                   running (healthy)
provider-influxdb-token-injector    running
provider-influxdb-proxy             running
provider-grafana                    running (healthy)
provider-telegraf                   running
provider-iot-bridge-api             running (healthy)
provider-caddy                      running (healthy)
```

---

## 4. Retrieve the step-ca Root CA Fingerprint

Tenant-Stacks and devices need to trust the Root CA.  Export the fingerprint with:

```bash
docker compose exec step-ca step ca fingerprint
```

Save this value as `STEP_CA_FINGERPRINT` — you will need it when setting up Tenant-Stacks
and enrolling devices.

To export the PEM certificate:

```bash
docker compose exec step-ca step ca root /tmp/root_ca.crt
docker compose cp step-ca:/tmp/root_ca.crt ./root_ca.crt
```

---

## 5. Finalise Keycloak Configuration

Keycloak is pre-seeded with the `cdm` and `provider` realms from templates.  After first
boot, retrieve the auto-generated OIDC client secrets and add them to your `.env`:

1. Open **`${EXTERNAL_URL}/auth/admin/cdm/console/`** and log in.
2. For each client (`grafana`, `iot-bridge`, `portal`, `influxdb-proxy`):  
   **Clients → \<client\> → Credentials → copy Secret**.
3. Switch to the **`provider`** realm (**`${EXTERNAL_URL}/auth/admin/provider/console/`**).
4. Navigate to **Clients → `rabbitmq-management` → Credentials → copy Secret**.
5. Update `.env`:
   ```
   GRAFANA_OIDC_SECRET=<from Keycloak cdm realm>
   BRIDGE_OIDC_SECRET=<from Keycloak cdm realm>
   PORTAL_OIDC_SECRET=<from Keycloak cdm realm>
   INFLUXDB_PROXY_OIDC_SECRET=<from Keycloak cdm realm>
   RABBITMQ_MANAGEMENT_OIDC_SECRET=<from Keycloak provider realm>
   ```
6. Restart the affected services:
   ```bash
   docker compose restart iot-bridge-api grafana rabbitmq keycloak
   ```

!!! info "RabbitMQ Management UI — SSO"
    After setting `RABBITMQ_MANAGEMENT_OIDC_SECRET` and restarting, the RabbitMQ Management UI
    at `/rabbitmq/` offers a **Sign in with Keycloak** button.  Users in the `provider` realm
    with the `rabbitmq.tag:administrator` scope can log in via SSO without a separate local
    RabbitMQ password.

### Grant superadmin cross-realm access

```bash
source .env
bash keycloak/init-tenants.sh
```

This grants the `${KC_ADMIN_USER}` account `realm-admin` rights on the `cdm` and `provider`
realms so you can manage them from the Keycloak Admin Console with a single login.

---

## 6. Verify Service Health

| Service | URL | Default credentials |
|---|---|---|
| CDM Dashboard (Caddy) | `http://localhost:8888` | — |
| Keycloak Admin (cdm) | `http://localhost:8888/auth/admin/cdm/console/` | `KC_ADMIN_USER` / `KC_ADMIN_PASSWORD` |
| Keycloak Admin (provider) | `http://localhost:8888/auth/admin/provider/console/` | same |
| Grafana | `http://localhost:8888/grafana/` | `admin` / `GRAFANA_ADMIN_PASSWORD` |
| RabbitMQ Management | `http://localhost:8888/rabbitmq/` | SSO via Keycloak **`provider`** realm (`KC_ADMIN_USER` / `KC_ADMIN_PASSWORD`) **or** local `admin` / `RABBITMQ_ADMIN_PASSWORD` |
| IoT Bridge API (Swagger) | `http://localhost:8888/api/docs` | — (requires OIDC JWT) |
| InfluxDB | `http://localhost:8086` | Authenticated transparently via oauth2-proxy + token-injector; Keycloak login uses `cdm-admin` / `changeme` (temporary) |
| step-ca | `https://localhost:9000/health` | — |

Replace `localhost` with the Codespaces forwarded URL when running in GitHub Codespaces.

!!! info "RabbitMQ Management UI — SSO"
    The RabbitMQ Management UI uses the **`provider`** Keycloak realm (not `cdm`).
    Click **Sign in with Keycloak** and use `KC_ADMIN_USER` / `KC_ADMIN_PASSWORD`
    (or `provider-operator` / `PROVIDER_OPERATOR_PASSWORD`).  The `cdm-admin` and
    `cdm-operator` accounts from the `cdm` realm cannot log into RabbitMQ.

!!! info "InfluxDB — transparent auth"
    InfluxDB is protected by `oauth2-proxy` (Keycloak `cdm` realm) plus an
    `influxdb-token-injector` Caddy sidecar that automatically adds the admin API token
    to every upstream request.  After the Keycloak login step, the InfluxDB UI opens
    directly without a second login screen.

---

## 7. Next Steps

- **Tenant-Stack** — [Installation → Tenant-Stack](tenant-stack.md) *(Phase 2)*  
  Set up a customer tenant that connects to this Provider-Stack.
- **Device-Stack** — [Installation → Device-Stack](device-stack.md)  
  Simulate an IoT device enrolling against a Tenant-Stack.
- **Architecture** — [Architecture → Stack Topology](../architecture/stack-topology.md)  
  Understand how Provider-Stack, Tenant-Stack, and Device-Stack interact.
