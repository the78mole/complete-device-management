# Tenant-Stack Setup

Each customer (tenant) operates an independent instance of the Tenant-Stack.  It provides
all device-facing services and optionally connects to a shared Provider-Stack via the JOIN
workflow to establish a chain of trust and cross-tenant telemetry forwarding.

---

## Services

| Service | Container prefix | Role |
|---|---|---|
| Caddy | `{TENANT_ID}-caddy` | Reverse proxy, single entry point on `:8888` |
| Keycloak | `{TENANT_ID}-keycloak` | Tenant realm, OIDC SSO for all services |
| ThingsBoard | `{TENANT_ID}-thingsboard` | Device registry, MQTT, rule engine, dashboards |
| hawkBit | `{TENANT_ID}-hawkbit` | OTA campaigns and artefact storage |
| step-ca | `{TENANT_ID}-step-ca` | Issuing Sub-CA (optionally signed by Provider Root CA) |
| WireGuard | `{TENANT_ID}-wireguard` | Device VPN server |
| Terminal Proxy | `{TENANT_ID}-terminal-proxy` | Browser terminal via WireGuard |
| InfluxDB | `{TENANT_ID}-influxdb` | Device telemetry time-series |
| Grafana | `{TENANT_ID}-grafana` | Tenant dashboards |
| IoT Bridge API | `{TENANT_ID}-iot-bridge-api` | Device enrollment, cert issuance, WG provisioning |

---

## Port Map

| Service | Default Port | Protocol | Notes |
|---|---|---|---|
| Caddy (entry point) | 8888 | HTTP/HTTPS | Path-based routing for all services |
| ThingsBoard UI | 9090 | HTTP | Direct port (SPA sub-path limitation) |
| ThingsBoard MQTT TLS | 8883 | MQTTS / mTLS | Direct, device connections |
| InfluxDB / oauth2-proxy | 8086 | HTTP | Direct port (SPA limitation) |
| step-ca | 9000 | HTTPS | Direct, device cert enrollment |
| WireGuard | 51820 | UDP | Direct, device VPN |
| Keycloak | `/auth/` via Caddy | HTTP | |
| Grafana | `/grafana/` via Caddy | HTTP | |
| hawkBit | `/hawkbit/` via Caddy | HTTP | |
| IoT Bridge API | `/api/` via Caddy | HTTP | |
| Terminal Proxy | `/terminal/` via Caddy | WebSocket | |
| PKI (step-ca) | `/pki/` via Caddy | HTTPS upstream | |

!!! info "Multiple tenant instances"
    When running more than one tenant on the same host, each instance must use a
    different `CADDY_PORT`, `WG_PORT` and `WG_INTERNAL_SUBNET`.  Example:

    | Tenant | CADDY_PORT | WG_PORT | WG_INTERNAL_SUBNET |
    |---|---|---|---|
    | tenant1 | 8888 | 51820 | 10.8.1.0 |
    | tenant2 | 8889 | 51821 | 10.8.2.0 |

---

## Prerequisites

- Docker Engine ≥ 24 and Docker Compose v2
- (Optional) A running Provider-Stack for Sub-CA signing and telemetry forwarding
- Port `51820/udp` open in the firewall for WireGuard
- Port `8883/tcp` open for device MQTT TLS connections

---

## Quick Start (standalone mode)

In standalone mode the Tenant Sub-CA starts as a self-signed Root CA.  The JOIN workflow
with the Provider-Stack is optional and can be completed later.

```bash
cd tenant-stack
cp .env.example .env
```

Edit `.env` and change every line marked `# [CHANGE ME]`.  At minimum set:

```bash
TENANT_ID=tenant1
TENANT_DISPLAY_NAME="Acme Devices GmbH"
EXTERNAL_URL=http://localhost:8888
```

Generate random secrets:

```bash
# Helper: generate a 32-char random hex string
rnd() { openssl rand -hex 16; }

sed -i \
  -e "s/KC_DB_PASSWORD=changeme/KC_DB_PASSWORD=$(rnd)/" \
  -e "s/KC_ADMIN_PASSWORD=changeme/KC_ADMIN_PASSWORD=$(rnd)/" \
  -e "s/GRAFANA_OIDC_SECRET=changeme/GRAFANA_OIDC_SECRET=$(rnd)/" \
  -e "s/TB_OIDC_SECRET=changeme/TB_OIDC_SECRET=$(rnd)/" \
  -e "s/HB_OIDC_SECRET=changeme/HB_OIDC_SECRET=$(rnd)/" \
  -e "s/BRIDGE_OIDC_SECRET=changeme/BRIDGE_OIDC_SECRET=$(rnd)/" \
  -e "s/PORTAL_OIDC_SECRET=changeme/PORTAL_OIDC_SECRET=$(rnd)/" \
  -e "s/INFLUX_PROXY_OIDC_SECRET=changeme/INFLUX_PROXY_OIDC_SECRET=$(rnd)/" \
  -e "s/INFLUX_TOKEN=my-super-secret-influx-token/INFLUX_TOKEN=$(rnd)$(rnd)/" \
  .env
```

Start the stack:

```bash
docker compose up -d
```

Wait for all services to be healthy:

```bash
docker compose ps
```

Then **initialise the step-ca provisioner** (run once):

```bash
docker compose exec ${TENANT_ID:-tenant1}-step-ca /usr/local/bin/init-sub-ca.sh
```

The script prints the `STEP_CA_FINGERPRINT` — copy it into `.env`:

```bash
STEP_CA_FINGERPRINT=<output from above>
```

Restart IoT Bridge API to pick it up:

```bash
docker compose restart iot-bridge-api
```

The landing page is now available at `http://localhost:8888`.

---

## Keycloak Realm Setup

The Tenant Keycloak realm is imported automatically on first start from
`keycloak/realms/realm-tenant.json.tpl`.  Three bootstrap users are created:

| User | Role | Initial password env var |
|---|---|---|
| `admin` | `cdm-admin` | `TENANT_ADMIN_PASSWORD` |
| `operator` | `cdm-operator` | `TENANT_OPERATOR_PASSWORD` |
| `viewer` | `cdm-viewer` | `TENANT_VIEWER_PASSWORD` |

!!! warning "Temporary passwords"
    All bootstrap user passwords are marked `"temporary": true`.  Users must
    choose a new password on first login through the Account Portal at
    `/auth/realms/{TENANT_ID}/account/`.

---

## ThingsBoard Provisioning (optional)

ThingsBoard needs a tenant account created via its System Admin API.  Use the
provisioning profile:

```bash
# Start only the provision helper (runs once and exits)
docker compose --profile provision up thingsboard-provision
```

---

## JOIN Workflow (connecting to a Provider-Stack)

The JOIN workflow links the Tenant Sub-CA to the Provider Root CA and optionally
forwards device telemetry to the Provider RabbitMQ.

**Step 1 – Get the Provider Root CA fingerprint:**

```bash
# On the machine running the Provider-Stack:
docker compose exec provider-step-ca step ca fingerprint
```

**Step 2 – Set Provider vars in `tenant-stack/.env`:**

```bash
STEP_CA_PROVIDER_URL=https://<provider-host>:9000
STEP_CA_PROVIDER_FINGERPRINT=<fingerprint from step 1>
STEP_CA_PROVIDER_ADMIN_PROVISIONER=cdm-admin@cdm.local
STEP_CA_PROVIDER_ADMIN_PASSWORD=<provider step-ca admin password>
```

**Step 3 – Run the Sub-CA signing script:**

```bash
docker compose restart step-ca   # restart to pick up new env vars
docker compose exec ${TENANT_ID:-tenant1}-step-ca /usr/local/bin/init-sub-ca.sh
```

The Tenant Issuing CA certificate is now signed by the Provider Root CA.  All
device certificates issued by this Tenant Sub-CA will be trusted by any service
that trusts the Provider Root CA chain.

---

## Enabling mTLS for MQTT

Once the Sub-CA is signed and device certs are available:

1. Set the following in `.env`:
   ```bash
   MQTT_SSL_ENABLED=true
   MQTT_SSL_CLIENT_AUTHENTICATION=REQUIRED
   ```
2. Issue a server certificate for ThingsBoard MQTT:
   ```bash
   docker compose exec ${TENANT_ID:-tenant1}-step-ca step ca certificate \
     thingsboard /etc/tb-certs/mqttserver.pem /etc/tb-certs/mqttserver-private.pem \
     --provisioner iot-bridge \
     --provisioner-password-file /run/secrets/step-ca-password
   ```
3. Restart ThingsBoard: `docker compose restart thingsboard`

---

## Updating the stack

```bash
docker compose pull
docker compose up -d --remove-orphans
```

---

## See Also

- [Architecture → Stack Topology](../architecture/stack-topology.md)
- [Architecture → PKI](../architecture/pki.md)
- [Architecture → Identity & Access Management](../architecture/iam.md)
- [Provider-Stack Setup](provider-stack.md)
- [First Device](../getting-started/first-device.md)
