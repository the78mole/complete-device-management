# Keycloak Skill – CDM Platform

> **Scope**: This file gives GitHub Copilot precise knowledge of the Keycloak deployment in
> this repository so it can answer questions, generate Admin API calls, and guide realm
> management tasks correctly.

---

## 1. Deployment overview

| Property | Value |
|---|---|
| Version | Keycloak 26.x (quay.io/keycloak/keycloak:26.5) |
| Base path | `/auth` (`KC_HTTP_RELATIVE_PATH=/auth`) |
| Admin console | `/auth/admin/` |
| Admin CLI token endpoint | `/auth/realms/master/protocol/openid-connect/token` |
| Proxy mode | `KC_PROXY_HEADERS=xforwarded` |
| Database | PostgreSQL 18 (`cdm-keycloak-db`, DB name `keycloak`) |
| Image build context | `cloud-infrastructure/keycloak/` |
| Dockerfile | `cloud-infrastructure/keycloak/Dockerfile` |
| Entrypoint | `cloud-infrastructure/keycloak/docker-entrypoint.sh` |

Keycloak is started with `start-dev --import-realm`.

---

## 2. Realm structure

### 2.1 master (built-in)

The Keycloak technical admin realm — **never used for application logins**.

| Item | Value |
|---|---|
| Admin user | `${KC_ADMIN_USER}` (default `admin`) |
| Admin password | `${KC_ADMIN_PASSWORD}` (default `changeme`) |
| Admin console URL | `/auth/admin/master/console/` |

### 2.2 cdm — Complete Device Management

Main application realm.  All platform services (ThingsBoard, Grafana, hawkBit, etc.) use
OIDC clients registered here.

**Realm roles**

| Role | Description |
|---|---|
| `cdm-admin` | Platform administrator |
| `cdm-operator` | Fleet operator |
| `cdm-viewer` | Read-only access |

**Example users**

| Username | Role | Initial password |
|---|---|---|
| `cdm-admin` | `cdm-admin` | `changeme` (temporary) |
| `cdm-operator` | `cdm-operator` | `changeme` (temporary) |

**OIDC clients**

| Client ID | Service | Type | Secret env var |
|---|---|---|---|
| `hawkbit` | hawkBit Update Server | confidential | `HB_OIDC_SECRET` |
| `thingsboard` | ThingsBoard | confidential | `TB_OIDC_SECRET` |
| `grafana` | Grafana | confidential | `GRAFANA_OIDC_SECRET` |
| `iot-bridge` | IoT Bridge API | confidential + service-account | `BRIDGE_OIDC_SECRET` |
| `terminal-proxy` | Terminal Proxy | public | — |

All `redirectUris` and `webOrigins` are set to `*` (wildcard) to support dynamic Codespaces hostnames.

**Template file**: `cloud-infrastructure/keycloak/realms/realm-cdm.json.tpl`

### 2.3 provider — Platform Operations

Realm for the platform operations team.  Has no OIDC clients; purely for human operator identity.

| Role | Description |
|---|---|
| `platform-admin` | Full administrative access to CDM platform and all tenants |
| `platform-operator` | Day-to-day operations; read-only on tenants |

**Users**

| Username | Role | Password | Notes |
|---|---|---|---|
| `${KC_ADMIN_USER}` | `platform-admin` | `${KC_ADMIN_PASSWORD}` (non-temporary) | Same credentials as master admin — true superadmin |
| `provider-operator` | `platform-operator` | `${PROVIDER_OPERATOR_PASSWORD}` (temporary) | — |

**Admin console**: `/auth/admin/provider/console/`  
**Account portal**: `/auth/realms/provider/account/`  
**Template file**: `cloud-infrastructure/keycloak/realms/realm-provider.json.tpl`

### 2.4 tenant1 — Acme Devices GmbH

First example tenant realm.  Roles mirror the `cdm` realm.

**Users**

| Username | Role | Email | Initial password env var |
|---|---|---|---|
| `alice` | `cdm-admin` | alice@acme-devices.example.com | `TENANT1_ADMIN_PASSWORD` |
| `bob` | `cdm-operator` | bob@acme-devices.example.com | `TENANT1_OPERATOR_PASSWORD` |
| `carol` | `cdm-viewer` | carol@acme-devices.example.com | `TENANT1_VIEWER_PASSWORD` |

**Admin console**: `/auth/admin/tenant1/console/`  
**Account portal**: `/auth/realms/tenant1/account/`  
**Template file**: `cloud-infrastructure/keycloak/realms/realm-tenant1.json.tpl`

### 2.5 tenant2 — Beta Industries Ltd

Second example tenant realm.

**Users**

| Username | Role | Email | Initial password env var |
|---|---|---|---|
| `dave` | `cdm-admin` | dave@beta-industries.example.com | `TENANT2_ADMIN_PASSWORD` |
| `eve` | `cdm-operator` | eve@beta-industries.example.com | `TENANT2_OPERATOR_PASSWORD` |
| `frank` | `cdm-viewer` | frank@beta-industries.example.com | `TENANT2_VIEWER_PASSWORD` |

**Admin console**: `/auth/admin/tenant2/console/`  
**Account portal**: `/auth/realms/tenant2/account/`  
**Template file**: `cloud-infrastructure/keycloak/realms/realm-tenant2.json.tpl`

---

## 3. Bootstrapping process

### 3.1 Realm import (automatic on every container start)

`cloud-infrastructure/keycloak/docker-entrypoint.sh` runs before Keycloak starts:

1. Iterates over every `*.json.tpl` in `/opt/keycloak/data/import-template/`
2. Applies `sed` substitution of all `${VAR}` placeholders
3. Writes rendered JSON to `/opt/keycloak/data/import/`
4. Keycloak starts with `--import-realm` → imports all files in that directory
5. **Existing realms are skipped** (Keycloak behaviour: "Realm X already exists. Import skipped")

### 3.2 Cross-realm admin wiring (manual, once)

After the first successful start, run:

```bash
cd cloud-infrastructure
source .env
bash keycloak/init-tenants.sh
```

`init-tenants.sh` uses the Keycloak Admin REST API to:
- Create/verify the `${KC_ADMIN_USER}` account in the **master** realm
- Grant `realm-admin` role on the `tenant1-realm`, `tenant2-realm`, and `provider-realm` clients

After this, the superadmin can access `/auth/admin/<tenant>/console/` with their normal credentials.

---

## 4. Template variable reference

All variables are substituted in every `*.json.tpl` file by `docker-entrypoint.sh`.

| Variable | Used in realm | Purpose |
|---|---|---|
| `${KC_ADMIN_USER}` | provider | Provider superadmin username |
| `${KC_ADMIN_PASSWORD}` | provider | Provider superadmin password |
| `${HB_OIDC_SECRET}` | cdm | hawkBit OIDC client secret |
| `${TB_OIDC_SECRET}` | cdm | ThingsBoard OIDC client secret |
| `${GRAFANA_OIDC_SECRET}` | cdm | Grafana OIDC client secret |
| `${BRIDGE_OIDC_SECRET}` | cdm | IoT Bridge OIDC client secret |
| `${PROVIDER_OPERATOR_PASSWORD}` | provider | provider-operator initial password |
| `${TENANT1_ADMIN_PASSWORD}` | tenant1 | alice initial password |
| `${TENANT1_OPERATOR_PASSWORD}` | tenant1 | bob initial password |
| `${TENANT1_VIEWER_PASSWORD}` | tenant1 | carol initial password |
| `${TENANT2_ADMIN_PASSWORD}` | tenant2 | dave initial password |
| `${TENANT2_OPERATOR_PASSWORD}` | tenant2 | eve initial password |
| `${TENANT2_VIEWER_PASSWORD}` | tenant2 | frank initial password |

---

## 5. Common Admin REST API patterns

All examples assume the platform is running locally.  Replace `localhost:8888` with the
Codespaces URL when running in GitHub Codespaces.

### Obtain an admin token

```bash
source cloud-infrastructure/.env

TOKEN=$(curl -sf \
  -X POST "http://localhost:8888/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli" \
  -d "username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASSWORD}" \
  | jq -r '.access_token')
```

### List realms

```bash
curl -sf -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8888/auth/admin/realms" | jq '.[].realm'
```

### List users in a realm

```bash
REALM=tenant1
curl -sf -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8888/auth/admin/realms/${REALM}/users" \
  | jq '.[] | {username, email, enabled}'
```

### Create a user

```bash
REALM=tenant1
curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "http://localhost:8888/auth/admin/realms/${REALM}/users" \
  -d '{
    "username": "newuser",
    "email": "newuser@example.com",
    "enabled": true,
    "emailVerified": true,
    "credentials": [{"type":"password","value":"changeme","temporary":true}]
  }'
```

### Assign a realm role to a user

```bash
REALM=tenant1
USER_ID=$(curl -sf -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8888/auth/admin/realms/${REALM}/users?username=newuser&exact=true" \
  | jq -r '.[0].id')

ROLE=$(curl -sf -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8888/auth/admin/realms/${REALM}/roles/cdm-operator" \
  | jq -c '{id,name}')

curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "http://localhost:8888/auth/admin/realms/${REALM}/users/${USER_ID}/role-mappings/realm" \
  -d "[${ROLE}]"
```

### Reset a user's password

```bash
REALM=tenant1
USER_ID=<uuid>
curl -sf -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "http://localhost:8888/auth/admin/realms/${REALM}/users/${USER_ID}/reset-password" \
  -d '{"type":"password","value":"newpassword","temporary":true}'
```

### List OIDC clients in a realm

```bash
REALM=cdm
curl -sf -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8888/auth/admin/realms/${REALM}/clients" \
  | jq '.[] | {clientId, enabled, publicClient}'
```

### Get/regenerate a client secret

```bash
REALM=cdm
CLIENT_UUID=$(curl -sf -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8888/auth/admin/realms/${REALM}/clients?clientId=grafana" \
  | jq -r '.[0].id')

# Get current secret
curl -sf -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8888/auth/admin/realms/${REALM}/clients/${CLIENT_UUID}/client-secret" \
  | jq '.value'

# Regenerate
curl -sf -X POST -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8888/auth/admin/realms/${REALM}/clients/${CLIENT_UUID}/client-secret" \
  | jq '.value'
```

---

## 6. Adding a new realm

1. Create `cloud-infrastructure/keycloak/realms/realm-<name>.json.tpl`  
   (copy `realm-tenant1.json.tpl` as starting point)
2. Add any new `${NEW_VAR}` password placeholders  
3. Register them in `docker-entrypoint.sh` as new `-e "s|${NEW_VAR}|...|g"` lines  
4. Add the variables to `docker-compose.yml` under the `keycloak:` `environment:` block  
5. Add them to `.env` and `.env.example`  
6. Add them to `init-tenants.sh` `MANAGED_REALMS` array  
7. Rebuild and restart:
   ```bash
   cd cloud-infrastructure
   docker compose build keycloak
   docker compose up -d keycloak
   ```
8. Run `keycloak/init-tenants.sh` to grant the superadmin cross-realm access

---

## 7. File map

```
cloud-infrastructure/
  keycloak/
    Dockerfile                     Image build: copies realms/ and entrypoint
    docker-entrypoint.sh           Template loop: sed substitution → import/
    init-tenants.sh                Post-boot: cross-realm realm-admin grants
    realms/
      realm-cdm.json.tpl           cdm realm  (platform OIDC clients + users)
      realm-provider.json.tpl      provider realm  (platform ops team)
      realm-tenant1.json.tpl       Acme Devices GmbH
      realm-tenant2.json.tpl       Beta Industries Ltd
```
