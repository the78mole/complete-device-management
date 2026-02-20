# Identity & Access Management — Keycloak

Keycloak is the central Identity Provider (IdP) for the entire platform. All user-facing services delegate authentication to Keycloak via OpenID Connect (OIDC).

---

## Realm Structure

A dedicated realm named **`cdm`** is pre-configured with:

- **OIDC Clients:** `thingsboard`, `hawkbit`, `grafana`
- **Default Roles:** `cdm-admin`, `cdm-operator`, `cdm-viewer`
- **Password Policy:** min 12 characters, no dictionary words
- **Session Timeout:** 8 hours (access token 5 minutes, refresh token 30 minutes)

The realm export is at `cloud-infrastructure/keycloak/realm-export.json`. It is imported automatically on first boot via `docker-entrypoint.sh`.

---

## OIDC Client Configuration

### ThingsBoard

| Setting | Value |
|---|---|
| Client ID | `thingsboard` |
| Client Protocol | `openid-connect` |
| Access Type | `confidential` |
| Valid Redirect URIs | `http://localhost:8080/*` |
| Roles mapped to TB roles | `cdm-admin` → `TENANT_ADMIN`; `cdm-operator` → `CUSTOMER_USER` |

### hawkBit

| Setting | Value |
|---|---|
| Client ID | `hawkbit` |
| Access Type | `confidential` |
| Valid Redirect URIs | `http://localhost:8090/*` |

### Grafana

| Setting | Value |
|---|---|
| Client ID | `grafana` |
| Access Type | `confidential` |
| Valid Redirect URIs | `http://localhost:3000/*` |

---

## Role-Based Access

| Role | ThingsBoard | hawkBit | Grafana |
|---|---|---|---|
| `cdm-admin` | Tenant Admin | Full access | Admin |
| `cdm-operator` | Customer User | Read + trigger deployments | Editor |
| `cdm-viewer` | Read-only | Read-only | Viewer |

---

## Updating Client Secrets

After the first boot, Keycloak generates new client secrets. Retrieve them:

1. Log in to Keycloak admin: **http://localhost:8180** → `cdm` realm → **Clients**.
2. For each client (`thingsboard`, `hawkbit`, `grafana`), go to **Credentials** → copy the **Secret**.
3. Update `.env`:
   ```
   TB_KEYCLOAK_CLIENT_SECRET=<thingsboard secret>
   HAWKBIT_KEYCLOAK_CLIENT_SECRET=<hawkbit secret>
   GRAFANA_KEYCLOAK_CLIENT_SECRET=<grafana secret>
   ```
4. Restart the affected services:
   ```bash
   docker compose restart thingsboard hawkbit grafana
   ```

---

## Multi-Tenancy

The `tenant-sync-service` (part of `iot-bridge-api`) listens to Keycloak events. When a new organisation is created in Keycloak, it automatically:

1. Creates a matching **Tenant** in ThingsBoard.
2. Creates a matching **Organisation** in Grafana.
3. Creates a hawkBit **tenant** group (if hawkBit PE multi-tenancy is enabled).

Endpoint: `POST /webhooks/keycloak/tenant-created` in `iot-bridge-api`.

---

## Security Considerations

!!! danger "Default Admin Password"
    Change `KEYCLOAK_ADMIN_PASSWORD` in `.env` before exposing Keycloak to any network.

!!! tip "Brute-Force Protection"
    Enable Keycloak's built-in brute-force detection: **Realm Settings → Security Defenses → Brute Force Detection**.

!!! tip "HTTPS in Production"
    In production, place Keycloak behind a TLS-terminating reverse proxy. Update all `Valid Redirect URIs` to `https://`.
