# Provider-Stack Setup

The Provider-Stack is the **trust anchor** of the entire CDM platform: it hosts the Root CA,
the central MQTT broker, and the management API that Tenant-Stacks register against.

This guide covers three deployment modes.  Choose the one that matches your situation:

| Mode | When to use |
|---|---|
| [A — Development (DevContainer / Codespaces)](#mode-a-development-devcontainer--codespaces) | Evaluating, developing, running demos — no real domain needed |
| [B — Test / On-Prem (no public domain)](#mode-b-test--on-prem-no-public-domain) | Internal server, team testing — domain is optional |
| [C — Production (real domain + Let's Encrypt)](#mode-c-production-real-domain--lets-encrypt) | Public deployment, customer-facing — HTTPS via Let's Encrypt |

All three modes share the same [common post-setup steps](#common-post-setup-steps) once the
containers are running.

---

## Prerequisites

| Requirement | Min version | Notes |
|---|---|---|
| Docker | 24.x | |
| Docker Compose | 2.20 | Ships with Docker Desktop |
| RAM | 6 GB | 8 GB recommended |
| Disk | 10 GB free | InfluxDB data grows over time |
| OS | Linux (amd64) | macOS works for development; Windows via WSL 2 |
| `git` | 2.40+ | |
| `step` CLI | 0.25+ | Host-side cert inspection only; not required inside containers |

---

## Mode A — Development (DevContainer / Codespaces)

The fastest path.  No domain, no TLS — Caddy runs on plain HTTP port 8888.  In GitHub
Codespaces the port is automatically forwarded via a `*.app.github.dev` URL.

### A1 — Clone and enter the stack

```bash
git clone https://github.com/the78mole/complete-device-management.git
cd complete-device-management/provider-stack
```

### A2 — Create `.env`

```bash
cp .env.example .env
```

Minimal changes for **localhost**:

```dotenv
EXTERNAL_URL=http://localhost:8888
INFLUX_EXTERNAL_URL=http://localhost:8086
CADDY_SITE_ADDRESS=       # empty → Caddy listens on :8888
CADDY_AUTO_HTTPS=off
# Change all secrets:
KC_ADMIN_PASSWORD=<strong-password>
KC_DB_PASSWORD=<strong-password>
STEP_CA_PASSWORD=<strong-password>
STEP_CA_PROVISIONER_PASSWORD=<strong-password>
RABBITMQ_ADMIN_PASSWORD=<strong-password>
INFLUX_ADMIN_PASSWORD=<strong-password>    # min 8 chars
INFLUX_TOKEN=<random-token>
INFLUX_PROXY_COOKIE_SECRET=$(openssl rand -hex 32)
```

For **GitHub Codespaces**, additionally:

```dotenv
EXTERNAL_URL=https://<CODESPACE_NAME>-8888.app.github.dev
INFLUX_EXTERNAL_URL=https://<CODESPACE_NAME>-8086.app.github.dev
INFLUX_PROXY_COOKIE_SECURE=true
INFLUX_PROXY_COOKIE_SAMESITE=none
```

!!! tip "Find your Codespace name"
    Run `echo $CODESPACE_NAME` in the terminal, or read the forwarded URLs from the
    **Ports** tab in the VS Code sidebar.

!!! info "OIDC secrets on first boot"
    `GRAFANA_OIDC_SECRET`, `BRIDGE_OIDC_SECRET`, `INFLUXDB_PROXY_OIDC_SECRET`, and
    `RABBITMQ_MANAGEMENT_OIDC_SECRET` can remain as `changeme` for the initial start.
    You will copy the real Keycloak-generated values in step [A5](#a5----retrieve-oidc-secrets).

!!! danger "Never commit `.env`"
    The file is listed in `.gitignore`.  Keep it out of version control.

### A3 — Start the stack

```bash
docker compose up -d
```

Wait ~60 s (Keycloak needs up to 90 s on first boot), then check:

```bash
docker compose ps
```

Every container should show `healthy` or `running`:

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

### A4 — Initialise PKI provisioners (run once)

```bash
docker compose exec step-ca /usr/local/bin/init-provisioners.sh
```

The script prints the Root CA fingerprint at the end.  Save it in `.env`:

```dotenv
STEP_CA_FINGERPRINT=<printed value>
```

### A5 — Retrieve OIDC secrets

1. Open `${EXTERNAL_URL}/auth/admin/cdm/console/` and log in with `KC_ADMIN_USER` / `KC_ADMIN_PASSWORD`.
2. Copy the client secret for each entry below (**Clients → `<id>` → Credentials → copy Secret**):

   | Realm | Client ID | `.env` variable |
   |---|---|---|
   | `cdm` | `grafana` | `GRAFANA_OIDC_SECRET` |
   | `cdm` | `iot-bridge` | `BRIDGE_OIDC_SECRET` |
   | `cdm` | `portal` | `PORTAL_OIDC_SECRET` |
   | `cdm` | `influxdb-proxy` | `INFLUXDB_PROXY_OIDC_SECRET` |
   | `provider` | `rabbitmq-management` | `RABBITMQ_MANAGEMENT_OIDC_SECRET` |

3. Update `.env` and restart affected services:

```bash
docker compose restart keycloak grafana iot-bridge-api rabbitmq
```

### A6 — Grant superadmin cross-realm access

```bash
source .env
bash keycloak/init-tenants.sh
```

✅ The stack is fully operational.  Jump to [Verify Service Health](#verify-service-health).

---

## Mode B — Test / On-Prem (no public domain)

Running on a bare server (VM, NUC, cloud instance) without a public FQDN.
Caddy serves plain HTTP on a configurable port; TLS is not required.

### B1 — Clone, create `.env`

Follow [A1](#a1----clone-and-enter-the-stack) and [A2](#a2----create-env), then set:

```dotenv
# Replace with the actual server IP or internal DNS name
EXTERNAL_URL=http://192.168.1.100:8888      # or http://cdm.internal:8888
INFLUX_EXTERNAL_URL=http://192.168.1.100:8086
CADDY_SITE_ADDRESS=       # empty → plain HTTP :8888
CADDY_AUTO_HTTPS=off
```

Use `openssl rand -hex 16` / `openssl rand -hex 32` for every secret — never use
`changeme` in a shared environment.

### B2 — Open firewall ports

```bash
ufw allow 8888/tcp   # CDM Dashboard / Caddy
ufw allow 8086/tcp   # InfluxDB proxy (direct)
ufw allow 9000/tcp   # step-ca (optional; needed by Tenant-Stacks connecting from another host)
```

### B3 — Start, PKI, OIDC, init-tenants

Follow steps [A3](#a3----start-the-stack) → [A4](#a4----initialise-pki-provisioners-run-once) → [A5](#a5----retrieve-oidc-secrets) → [A6](#a6----grant-superadmin-cross-realm-access),
substituting `localhost` with your server IP or hostname.

---

## Mode C — Production (real domain + Let's Encrypt)

Caddy obtains a TLS certificate from Let's Encrypt automatically.  Requirements:

- A publicly reachable FQDN pointing to the server (e.g. `cdm.example.com`)
- Ports **80** and **443** open from the internet (for ACME HTTP-01 challenge)
- A valid e-mail address for Let's Encrypt expiry notifications

!!! warning "Port 80 must be reachable"
    Caddy uses ACME HTTP-01 to prove domain ownership.  Port 80 must be reachable from
    Let's Encrypt servers even if you redirect HTTP → HTTPS afterwards.

### C1 — Clone and enter the stack

Follow [A1](#a1----clone-and-enter-the-stack).

### C2 — Override Caddy port mapping for 80 + 443

Create `docker-compose.override.yml` next to `docker-compose.yml` (keeps the base file
clean and easier to update from upstream):

```yaml
# provider-stack/docker-compose.override.yml
services:
  caddy:
    ports:
      - "80:80"
      - "443:443"
```

### C3 — Create `.env`

```bash
cp .env.example .env
```

Production-specific settings:

```dotenv
# ── URLs ─────────────────────────────────────────────────────────────────────
EXTERNAL_URL=https://cdm.example.com          # your FQDN, no trailing slash
INFLUX_EXTERNAL_URL=https://influx.example.com  # see note below

# ── Caddy ─────────────────────────────────────────────────────────────────────
CADDY_SITE_ADDRESS=cdm.example.com   # Caddy requests LE cert for this domain
CADDY_AUTO_HTTPS=on
CADDY_ACME_EMAIL=ops@example.com     # Let's Encrypt notifications

# ── oauth2-proxy (HTTPS cookies required) ────────────────────────────────────
INFLUX_PROXY_COOKIE_SECURE=true
INFLUX_PROXY_COOKIE_SAMESITE=none

# ── Generate all secrets fresh ───────────────────────────────────────────────
KC_ADMIN_PASSWORD=$(openssl rand -hex 16)
KC_DB_PASSWORD=$(openssl rand -hex 16)
STEP_CA_PASSWORD=$(openssl rand -hex 32)
STEP_CA_PROVISIONER_PASSWORD=$(openssl rand -hex 32)
RABBITMQ_ADMIN_PASSWORD=$(openssl rand -hex 16)
INFLUX_ADMIN_PASSWORD=$(openssl rand -hex 16)
INFLUX_TOKEN=$(openssl rand -hex 32)
INFLUX_PROXY_COOKIE_SECRET=$(openssl rand -hex 32)
PORTAL_SESSION_SECRET=$(openssl rand -hex 32)
```

!!! note "InfluxDB TLS in production"
    InfluxDB is exposed on a separate port (SPA webpack limitation).  For production
    TLS, add `influx.example.com` as a second DNS record pointing to the same server
    and extend `docker-compose.override.yml` with a second Caddy site block:
    ```yaml
    # In the caddy container's volumes, mount an extended Caddyfile that adds:
    # influx.example.com {
    #     reverse_proxy influxdb-proxy:4180
    # }
    ```
    A simpler alternative is to terminate TLS for port 8086 at a separate load
    balancer or cloud ingress.

### C4 — Start and verify TLS

```bash
docker compose up -d
docker compose logs caddy -f   # watch for "certificate obtained successfully"
```

Then:

```bash
curl -sv https://cdm.example.com/auth/realms/master/.well-known/openid-configuration \
  2>&1 | grep -E "SSL|issuer|subject"
```

### C5 — PKI, OIDC, init-tenants

Follow steps [A4](#a4----initialise-pki-provisioners-run-once) → [A5](#a5----retrieve-oidc-secrets) → [A6](#a6----grant-superadmin-cross-realm-access),
replacing `localhost:8888` with `https://cdm.example.com`.

---

## Common post-setup steps

### Export Root CA certificate (for Tenant-Stacks and devices)

```bash
docker compose exec step-ca step ca root /tmp/root_ca.crt
docker compose cp step-ca:/tmp/root_ca.crt ./root_ca.crt
step certificate inspect root_ca.crt   # verify on host
```

Distribute `root_ca.crt` and `STEP_CA_FINGERPRINT` to every Tenant-Stack and Device-Stack.

---

## Verify service health

| Service | Dev URL (localhost) | Credentials |
|---|---|---|
| **CDM Dashboard** | `http://localhost:8888` | — |
| **Keycloak Admin (cdm)** | `/auth/admin/cdm/console/` | `KC_ADMIN_USER` / `KC_ADMIN_PASSWORD` |
| **Keycloak Admin (provider)** | `/auth/admin/provider/console/` | same |
| **Grafana** | `/grafana/` | `admin` / `GRAFANA_ADMIN_PASSWORD` |
| **RabbitMQ Management** | `/rabbitmq/` | SSO: Keycloak **`provider`** realm (`KC_ADMIN_USER`) **or** local `admin` / `RABBITMQ_ADMIN_PASSWORD` |
| **IoT Bridge API (Swagger)** | `/api/docs` | requires OIDC JWT |
| **InfluxDB** | `http://localhost:8086` | SSO via Keycloak `cdm` realm; token-injector handles InfluxDB auth transparently |
| **step-ca health** | `https://localhost:9000/health` | returns `{"status":"ok"}` |

!!! warning "RabbitMQ: use the `provider` realm"
    The SSO button redirects to the **`provider`** realm.  Log in with
    `KC_ADMIN_USER` / `KC_ADMIN_PASSWORD` — the `cdm-admin` account does not work here.

!!! info "InfluxDB: no double login"
    After the Keycloak step, InfluxDB opens directly.  The `influxdb-token-injector`
    sidecar injects the admin API token on every upstream request.

---

## Next steps

- **Tenant-Stack** → [Installation → Tenant-Stack](tenant-stack.md)
- **Device-Stack** → [Installation → Device-Stack](device-stack.md)
- **Architecture** → [Architecture → Stack Topology](../architecture/stack-topology.md)
- **Troubleshooting** → [Use Cases → Troubleshooting](../use-cases/troubleshooting.md)
