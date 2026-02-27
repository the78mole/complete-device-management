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
| Database | PostgreSQL 18 (`keycloak-db`, DB name `keycloak`) |
| Image build context | `provider-stack/keycloak/` |
| Dockerfile | `provider-stack/keycloak/Dockerfile` |
| Entrypoint | `provider-stack/keycloak/docker-entrypoint.sh` |
| Managed realms | `cdm`, `provider` only (tenant realms live in each Tenant-Stack) |

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
| `grafana` | Grafana (Provider Dashboards) | confidential | `GRAFANA_OIDC_SECRET` |
| `iot-bridge` | IoT Bridge API | confidential + service-account | `BRIDGE_OIDC_SECRET` |
| `portal` | CDM Tenant Portal (iot-bridge-api) | confidential | `PORTAL_OIDC_SECRET` |
| `influxdb-proxy` | InfluxDB oauth2-proxy sidecar | confidential | `INFLUXDB_PROXY_OIDC_SECRET` |

> **hawkBit, ThingsBoard, Terminal Proxy** OIDC clients are registered in each
> Tenant-Stack's own Keycloak instance (Phase 2), not in the provider-stack `cdm` realm.

All `redirectUris` and `webOrigins` are set to `*` (wildcard) to support dynamic Codespaces hostnames.

> **Grafana — realm-roles mapper**: The `grafana` client has a `realm-roles` ProtocolMapper
> (`oidc-usermodel-realm-role-mapper`) that injects all realm roles as a flat array into the
> `roles` claim of the access token.  Grafana maps this claim to its internal role via
> `GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH`.

**Admin console**: `/auth/admin/cdm/console/`  
**Account portal**: `/auth/realms/cdm/account/`  
**Template file**: `provider-stack/keycloak/realms/realm-cdm.json.tpl`

### 2.3 provider — Platform Operations

Realm for the platform operations team.

| Role | Description |
|---|---|
| `platform-admin` | Full administrative access to CDM platform and all tenants |
| `platform-operator` | Day-to-day operations; read-only on tenants |

**Users**

| Username | Role | Password | Notes |
|---|---|---|---|
| `${KC_ADMIN_USER}` | `platform-admin` | `${KC_ADMIN_PASSWORD}` (non-temporary) | Same credentials as master admin — true superadmin |
| `provider-operator` | `platform-operator` | `${PROVIDER_OPERATOR_PASSWORD}` (temporary) | — |

**OIDC clients**

| Client ID | Service | Type | Secret env var |
|---|---|---|---|
| `grafana-broker` | Grafana identity-broker (cdm realm federation) | confidential | `GRAFANA_BROKER_SECRET` |
| `rabbitmq-management` | RabbitMQ Management UI (OAuth2 SSO) | confidential | `RABBITMQ_MANAGEMENT_OIDC_SECRET` |

**RabbitMQ OAuth2 integration — `rabbitmq-management` client**

The `rabbitmq-management` client enables single-sign-on into the RabbitMQ management UI
for `provider` realm users.  The following Keycloak client scopes are registered in the
`provider` realm and assigned as *default* scopes on `rabbitmq-management`:

> **Important:** The standard OIDC scopes `openid`, `profile`, and `email` **must** exist
> in the `provider` realm as client scopes (they are not auto-created by Keycloak on import).
> Without them RabbitMQ shows `ErrorResponse: Invalid scopes: openid profile` when attempting
> SSO login.  `realm-provider.json.tpl` defines these scopes; if they are missing from a
> running deployment run the quick-fix below (→ Section 9).

| Scope name | Grants |
|---|---|
| `rabbitmq.tag:administrator` | Full management UI access |
| `rabbitmq.read:*/*` | Read all vhosts/queues |
| `rabbitmq.write:*/*` | Write all vhosts/queues |
| `rabbitmq.configure:*/*` | Configure all vhosts/queues |
| `rabbitmq.tag:monitoring` | Read-only UI access (optional scope) |

An **audience mapper** (`oidc-audience-mapper`) adds `rabbitmq` as a custom `aud` claim to
every access token issued for this client — required by RabbitMQ's OAuth2 backend.

**Admin console**: `/auth/admin/provider/console/`  
**Account portal**: `/auth/realms/provider/account/`  
**Template file**: `provider-stack/keycloak/realms/realm-provider.json.tpl`

### 2.4 Tenant realms — Phase 2

> **Note: Tenant realms (`tenant1`, `tenant2`, …) are NOT part of the Provider-Stack.**
> Each Tenant-Stack runs its own dedicated Keycloak instance and registers its realm as an
> Identity Provider inside the `cdm` realm via Keycloak Realm-Federation (see `architecture/iam.md`).
> The legacy `realm-tenant1.json.tpl` and `realm-tenant2.json.tpl` files remain in
> `cloud-infrastructure/keycloak/realms/` for reference until Phase 2 is complete.

---

## 3. Bootstrapping process

### 3.1 Realm import (automatic on every container start)

`provider-stack/keycloak/docker-entrypoint.sh` runs before Keycloak starts:

1. Iterates over every `*.json.tpl` in `/opt/keycloak/data/import-template/`
2. Applies `sed` substitution of all `${VAR}` placeholders
3. Writes rendered JSON to `/opt/keycloak/data/import/`
4. Keycloak starts with `--import-realm` → imports all files in that directory
5. **Existing realms are skipped** (Keycloak behaviour: "Realm X already exists. Import skipped")
6. **Background post-start hook** — a background subshell (`&`) polls every 5 s until
   Keycloak is ready, then uses `kcadm.sh` to apply two idempotent post-boot changes to
   every non-master realm:
   - Adds the `account-audience` mapper to the `account-console` client (required for
     `aud: account` in the access token; KC 26 validates `aud` strictly)
   - Adds `manage-account` and `view-profile` as composites of `default-roles-{realm}` so
     newly created users automatically receive the Account REST API roles
   
   The subshell starts with `set +eu` to prevent the Keycloak `set -eu` entrypoint from
   terminating the retry loop on the first poll failure.

### 3.2 Cross-realm admin wiring (manual, once)

After the first successful start, run:

```bash
cd provider-stack
source .env
bash keycloak/init-tenants.sh
```

`init-tenants.sh` uses the Keycloak Admin REST API to:
- Create/verify the `${KC_ADMIN_USER}` account in the **master** realm
- Grant `realm-admin` role on the `cdm-realm` and `provider-realm` clients

After this, the superadmin can access `/auth/admin/<realm>/console/` with their normal credentials.

> **Tenant realms** are managed exclusively by Tenant-Stack instances.  When a tenant joins
> the platform (the JOIN workflow introduced in Phase 3), the IoT Bridge API automatically
> registers the Tenant-Stack Keycloak realm as an Identity Provider in the `cdm` realm.

---

## 4. Template variable reference

All variables are substituted in every `*.json.tpl` file by `docker-entrypoint.sh`.

| Variable | Used in realm | Purpose |
|---|---|---|
| `${KC_ADMIN_USER}` | provider | Provider superadmin username |
| `${KC_ADMIN_PASSWORD}` | provider | Provider superadmin password |
| `${GRAFANA_OIDC_SECRET}` | cdm | Grafana OIDC client secret |
| `${BRIDGE_OIDC_SECRET}` | cdm | IoT Bridge OIDC client secret |
| `${PORTAL_OIDC_SECRET}` | cdm | Portal OIDC client secret |
| `${INFLUXDB_PROXY_OIDC_SECRET}` | cdm | InfluxDB oauth2-proxy OIDC client secret |
| `${PROVIDER_OPERATOR_PASSWORD}` | provider | provider-operator initial password |

> **Tenant-specific variables** (`TENANT1_*`, `TENANT2_*`, `HB_OIDC_SECRET`, `TB_OIDC_SECRET`, …)
> belong to individual Tenant-Stack `.env` files, not to provider-stack.

---

## 5. Common Admin REST API patterns

All examples assume the platform is running locally.  Replace `localhost:8888` with the
Codespaces URL when running in GitHub Codespaces.

### Obtain an admin token

```bash
source provider-stack/.env

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
REALM=cdm
curl -sf -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8888/auth/admin/realms/${REALM}/users" \
  | jq '.[] | {username, email, enabled}'
```

### Create a user

```bash
REALM=cdm
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
REALM=cdm
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
REALM=cdm
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

1. Create `provider-stack/keycloak/realms/realm-<name>.json.tpl`  
   (copy `realm-cdm.json.tpl` as starting point)
2. Add any new `${NEW_VAR}` password placeholders  
3. Register them in `provider-stack/keycloak/docker-entrypoint.sh` as new `-e "s|${NEW_VAR}|...|g"` lines  
4. Add the variables to `provider-stack/docker-compose.yml` under the `keycloak:` `environment:` block  
5. Add them to `provider-stack/.env` and `provider-stack/.env.example`  
6. Add the realm to `provider-stack/keycloak/init-tenants.sh` `MANAGED_REALMS` array  
7. Rebuild and restart:
   ```bash
   cd provider-stack
   docker compose build keycloak
   docker compose up -d keycloak
   ```
8. Run `keycloak/init-tenants.sh` to grant the superadmin cross-realm access

> **Tenant realms** are NOT added here.  They are bootstrapped by the Tenant-Stack and
> federated into the `cdm` realm via Keycloak Identity Provider federation (Phase 3).

### Critical rules for new realm templates

- **Never include system clients** (`account`, `account-console`, `broker`, `security-admin-console`,
  `realm-management`) in the `"clients": []` array.  Keycloak auto-creates them; a duplicate import
  causes a PostgreSQL unique-key constraint violation that crashes startup.
- **Use `"attributes": { "post.logout.redirect.uris": "*" }`** for post-logout redirect on confidential
  clients — the field `"postLogoutRedirectUris"` is **not** recognised by KC 26 import and causes an
  `Unrecognized field` deserialization error.
- **Every user must have Account REST API roles**.  Include in every user's JSON:
  ```json
  "clientRoles": { "account": ["manage-account", "view-profile"] }
  ```
  Without these, the Account Console (`/auth/realms/<realm>/account/`) returns HTTP 403.
- **Rebuild the image** after every template change — templates are baked into the Docker image at
  build time, not mounted as a volume:
  ```bash
  cd provider-stack && docker compose build keycloak
  ```

---

## 7. Known pitfalls — Keycloak 26 specifics

### 7.1 Import JSON restrictions

| Mistake | Symptom | Fix |
|---|---|---|
| `"postLogoutRedirectUris": ["*"]` in a client | `Unrecognized field "postLogoutRedirectUris"` → crash | Use `"attributes": { "post.logout.redirect.uris": "*" }` |
| System client (`account-console`, `account`, `broker`, …) included in `clients[]` | `ERROR: duplicate key value violates unique constraint` → crash loop | Remove from template; use `kcadm.sh` post-boot hook for custom config |
| Using `jq` in KC container | `jq: command not found` | Use `python3 -c "import json…"` or `kcadm.sh` instead |

### 7.5 `KC_HOSTNAME` must include the sub-path when using `KC_HTTP_RELATIVE_PATH`

When `KC_HTTP_RELATIVE_PATH=/auth` is set (as in the provider-stack), `KC_HOSTNAME`
**must** include the full path prefix:

```yaml
# docker-compose.yml — Keycloak service
KC_HOSTNAME: "${EXTERNAL_URL:-http://localhost:8888}/auth"
```

If `KC_HOSTNAME` is set to the bare origin (`https://host:8888`) without `/auth`,
Keycloak generates all static asset URLs and form-action targets without the prefix:

- Asset URLs become `/resources/…` instead of `/auth/resources/…` → **404** → login page renders unstyled (black screen)
- Form actions point to `/realms/…` instead of `/auth/realms/…` → POST fails

In GitHub Codespaces the external URL changes per workspace.  Always set `EXTERNAL_URL`
to the exact Codespaces origin, including the correct port segment
(`https://<CODESPACE_NAME>-8888.app.github.dev`).

### 7.6 Standard OIDC scopes (`openid`, `profile`, `email`) are not auto-created

Keycloak does **not** automatically create the standard OIDC scopes when a realm is
imported from JSON.  Services that request `scope=openid profile` (most standard OAuth2
clients, including RabbitMQ Management) will fail with `Invalid scopes` if these scopes
have not been explicitly defined in the realm's `clientScopes` list.

`realm-provider.json.tpl` now includes full definitions for `openid`, `profile`, and
`email` with the standard protocol mappers.  If they are missing from a running deployment:

```bash
source provider-stack/.env
TOKEN=$(curl -sf -X POST \
  "${EXTERNAL_URL}/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Create the scopes in the provider realm
for SCOPE in openid profile email; do
  curl -sf -X POST "${EXTERNAL_URL}/auth/admin/realms/provider/client-scopes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${SCOPE}\",\"protocol\":\"openid-connect\"}"
done
```

Then assign the newly created scopes as default scopes to the `rabbitmq-management` client
(see Section 5 — REST API patterns).

### 7.7 python3 not available in the Keycloak container

`provider-stack/keycloak/docker-entrypoint.sh` includes a background hook that uses
`python3` for idempotent post-boot operations.  The Keycloak image (`quay.io/keycloak/keycloak`)
does **not** ship `python3`; the warning `python3: command not found` in the container logs
is harmless — the relevant operations are performed via `kcadm.sh` instead.  Do not add
`python3` to the Keycloak image; use `kcadm.sh` for all in-container operations.

### 7.2 Account Console — 403 on `/account/?userProfileMetadata=true`

Two independent requirements must both be satisfied:

| Requirement | Why | How |
|---|---|---|
| `aud: account` in access token | KC 26 validates JWT audience strictly | Add `account-audience` mapper (`oidc-audience-mapper`) to `account-console` client |
| `manage-account` **or** `view-profile` client role | Account REST API enforces role check | Add roles to user (template: `"clientRoles": {"account": ["manage-account","view-profile"]}`) |

The entrypoint background hook handles both requirements for all realms on every container start.

### 7.3 Caddy — large response headers

Keycloak sends large response headers (JWT `Set-Cookie`, long `Content-Security-Policy`).
Caddy handles these natively with its internal HTTP/2 buffering; the old nginx `proxy_buffer_size`
workaround is **not needed** in the provider-stack.

> **nginx is not used in the provider-stack.**  All ingress is handled by
> `provider-stack/caddy/Caddyfile`.  If you deploy a custom nginx in front, apply:
> ```nginx
> proxy_buffer_size       32k;
> proxy_buffers           8 32k;
> proxy_busy_buffers_size 64k;
> ```
> inside the `/auth/` location block.

### 7.4 kcadm.sh in background subshells

`docker-entrypoint.sh` uses `set -euo pipefail`.  Background subshells inherit these flags,
so the **first** failed `kcadm.sh` invocation (before Keycloak is ready) kills the entire
subshell.  Always begin background subshells with:

```sh
(
  set +eu
  # ... retry loop ...
) &
```

---

## 8. Tenant Portal

The IoT Bridge API (`glue-services/iot-bridge-api`) hosts a browser-facing tenant portal
at `/api/portal/`.  It implements an OIDC authorisation-code flow against the appropriate
Keycloak realm and renders a role-based service dashboard after successful login.

### Flow

```
GET  /api/portal/           → Tenant selection page (organisation ID input — no tenant list shown)
POST /api/portal/login      → Validates tenant, redirects to Keycloak realm login
GET  /api/portal/callback   → Code exchange, session setup
GET  /api/portal/dashboard  → Role-based service dashboard
GET  /api/portal/logout     → Session clear + Keycloak RP-initiated logout
```

### Dashboard service matrix

| Role | Services shown |
|---|---|
| `cdm-admin` / `platform-admin` | Keycloak Admin, ThingsBoard, Grafana, hawkBit, InfluxDB, RabbitMQ, IoT Bridge Swagger, step-ca, Account Portal |
| `cdm-operator` / `platform-operator` | ThingsBoard, Grafana, hawkBit, Account Portal |
| `cdm-viewer` | Grafana, Account Portal |

### Keycloak client requirements

Every realm that the portal should serve **must** have a confidential OIDC client:

```json
{
  "clientId": "portal",
  "publicClient": false,
  "secret": "<PORTAL_OIDC_SECRET>",
  "redirectUris": ["*"],
  "standardFlowEnabled": true,
  "attributes": { "post.logout.redirect.uris": "*" }
}
```

This client is included in `provider-stack/keycloak/realms/realm-cdm.json.tpl` and
`provider-stack/keycloak/realms/realm-provider.json.tpl` and is provisioned via API
by `init-tenants.sh` for existing deployments.  Each Tenant-Stack must also register
a `portal` client in its own realm.

### Environment variables (iot-bridge-api)

| Variable | Purpose |
|---|---|
| `EXTERNAL_URL` | Browser-facing base URL (e.g. `https://<codespaces-host>-8888.app.github.dev`) |
| `PORTAL_OIDC_SECRET` | Secret for the `portal` client — same across all realms in dev |
| `PORTAL_SESSION_SECRET` | Signs the encrypted session cookie — **change in production** |
| `PORTAL_TENANTS_JSON` | JSON map `{"<id>":{"name":"<Display Name>"}, ...}` of statically known realms/tenants; in provider-stack defaults to `{"cdm":{"name":"CDM Platform"}}`. Tenants are added here dynamically when they join (Phase 3). |



```
provider-stack/
  keycloak/
    Dockerfile                     Image build: copies realms/ and entrypoint
    docker-entrypoint.sh           Template loop: sed substitution → import/
    init-tenants.sh                Post-boot: cross-realm realm-admin grants
    realms/
      realm-cdm.json.tpl           cdm realm  (platform OIDC clients + users)
      realm-provider.json.tpl      provider realm  (platform ops team)
```

> **Tenant realms** (`realm-tenant.json.tpl`, etc.) live in each Tenant-Stack under
> `tenant-stack/keycloak/realms/` (Phase 2).

---

## 9. Maintenance scripts

Ready-to-use scripts live in `.github/skills/cdm-keycloak/scripts/`.
All scripts accept `BASE_URL` as a positional argument (default: `http://localhost:8888`).

| Script | Purpose | Usage |
|---|---|---|
| `kc-token.sh` | Obtain an admin token from master realm | `TOKEN=$(bash scripts/kc-token.sh [BASE_URL])` |
| `kc-apply-account-audience-mapper.sh` | Add `account-audience` mapper to `account-console` | `bash scripts/kc-apply-account-audience-mapper.sh [BASE_URL] [REALM …]` |
| `kc-apply-account-roles.sh` | Grant `manage-account`+`view-profile` to all users + `default-roles-{realm}` | `bash scripts/kc-apply-account-roles.sh [BASE_URL] [REALM …]` |
| `kc-force-logout.sh` | Invalidate all sessions for one or more users | `bash scripts/kc-force-logout.sh REALM USER [USER …] [-- BASE_URL]` |
| `kc-show-client-mappers.sh` | List all protocol mappers for a client | `bash scripts/kc-show-client-mappers.sh REALM CLIENT_ID [BASE_URL]` |
| `kc-debug-account-api.sh` | Diagnose Account REST API 403s for a user | `bash scripts/kc-debug-account-api.sh REALM USERNAME PASSWORD [BASE_URL]` |

### Quick-fix runbook — Account Console 403

If users get `403 Forbidden` on `/auth/realms/<realm>/account/`:

```bash
# 1. Apply account-audience mapper to all provider-stack realms
bash .github/skills/cdm-keycloak/scripts/kc-apply-account-audience-mapper.sh

# 2. Grant manage-account + view-profile to all existing users
bash .github/skills/cdm-keycloak/scripts/kc-apply-account-roles.sh

# 3. Force-logout the affected user so they get a fresh token
bash .github/skills/cdm-keycloak/scripts/kc-force-logout.sh cdm cdm-admin

# 4. (Optional) Verify the fix
bash .github/skills/cdm-keycloak/scripts/kc-debug-account-api.sh cdm cdm-admin <password>
```

For tenant realms (Tenant-Stack), pass the base URL and realm explicitly:
```bash
bash .github/skills/cdm-keycloak/scripts/kc-apply-account-audience-mapper.sh http://<tenant-host>:8888 tenant-realm-name
```

### Quick-fix runbook — Grafana OIDC role not recognized

If Grafana shows a user as `Viewer` despite having `cdm-admin` realm role:

```bash
# Verify the realm-roles mapper is present on the grafana client
bash .github/skills/cdm-keycloak/scripts/kc-show-client-mappers.sh cdm grafana
# Expect: "realm-roles" with protocolMapper = oidc-usermodel-realm-role-mapper

# Force token refresh
bash .github/skills/cdm-keycloak/scripts/kc-force-logout.sh cdm cdm-admin
```
