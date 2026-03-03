# CDM Skill — RabbitMQ OAuth2 / OIDC Integration

This document covers the RabbitMQ Management UI OAuth2 single-sign-on (SSO) integration
in the **provider-stack**, and all known compatibility issues with RabbitMQ 4.x.

---

## 1. Architecture overview

```
Browser → Caddy (/rabbitmq/) → RabbitMQ Management :15672
                                  ↓  OAuth2 OIDC redirect
                              Keycloak cdm realm (/auth/realms/cdm)
```

RabbitMQ uses the **`rabbitmq-management`** Keycloak client in the `cdm` realm.
Credentials (client ID + secret) are injected at container start via environment variables
from the `rabbitmq-management` entry in `provider-stack/docker-compose.yml`.

---

## 2. Configuration files

| File | Purpose |
|---|---|
| `provider-stack/rabbitmq/advanced.config.tpl` | Erlang config template — OAuth2 settings |
| `provider-stack/rabbitmq/rabbitmq.conf.tpl` | Main RabbitMQ config template |
| `provider-stack/rabbitmq/docker-entrypoint.sh` | Substitutes `EXTERNAL_URL_PLACEHOLDER` → `${EXTERNAL_URL}` at container start |

---

## 3. `advanced.config.tpl` — OAuth2 settings explained

```erlang
{rabbitmq_management, [
  {oauth_enabled, true},
  {oauth_client_id, "rabbitmq-management"},
  {oauth_client_secret, "RABBITMQ_MANAGEMENT_OIDC_SECRET_PLACEHOLDER"},
  {oauth_provider_url, "EXTERNAL_URL_PLACEHOLDER/auth/realms/cdm"}
  %% NOTE: oauth_provider_url must be the BROWSER-reachable URL (not internal Docker hostname).
  %% RabbitMQ 4.x forwards this URL directly to the browser for OIDC discovery.
]},
{rabbitmq_auth_backend_oauth2, [
  {resource_server_id, <<"rabbitmq">>},
  {extra_scopes_source, <<"rabbitmq_scopes">>},
  {jwks_url, "http://keycloak:8080/auth/realms/cdm/protocol/openid-connect/certs"},
  %% jwks_url can use the internal Docker hostname (server-to-server, no TLS)
  {issuer, "EXTERNAL_URL_PLACEHOLDER/auth/realms/cdm"}
  %% issuer must match the 'iss' claim in Keycloak JWTs.
  %% KC_HOSTNAME determines what Keycloak stamps into the 'iss' field.
  %% If KC_HOSTNAME = "https://host/auth", then iss = "https://host/auth/realms/cdm"
]}
```

The `docker-entrypoint.sh` performs a `sed` substitution:
```
EXTERNAL_URL_PLACEHOLDER  →  ${EXTERNAL_URL}   (value from .env)
RABBITMQ_MANAGEMENT_OIDC_SECRET_PLACEHOLDER  →  ${RABBITMQ_MANAGEMENT_OIDC_SECRET}
```

---

## 4. RabbitMQ 4.x breaking changes

### 4.1 `oauth_initiated_logon_type` removed

**Symptom:** `bootstrap.js` returns HTTP 500 with error:
```
no case clause matching <<"sp_initiated">>
```

**Cause:** The `oauth_initiated_logon_type` setting was removed in RabbitMQ 4.0.

**Fix:** Remove the line entirely from `advanced.config.tpl`.  The option no longer exists.

### 4.2 `oauth_authorization_endpoint` removed

Similarly, the `oauth_authorization_endpoint` key was removed in RabbitMQ 4.x.
Remove it from `advanced.config.tpl`; RabbitMQ now discovers the authorization endpoint
from the OIDC discovery document autonomously.

### 4.3 `oauth_provider_url` must be browser-reachable

In RabbitMQ 4.x the management UI JavaScript uses `oauth_provider_url` directly to
construct the OIDC discovery URL in the **browser**:
```
<oauth_provider_url>/.well-known/openid-configuration
```

In RabbitMQ 3.x this URL was only used server-side.

**Consequence for Codespaces / any non-localhost deployment:**
- ❌ `oauth_provider_url = "http://keycloak:8080/auth/realms/cdm"` — browser cannot resolve
  internal Docker hostnames → SSO button loads, then silently fails
- ✅ `oauth_provider_url = "https://<CODESPACE_NAME>-8888.app.github.dev/auth/realms/cdm"`

Always set `oauth_provider_url` to the same value as `EXTERNAL_URL` + `/auth/realms/cdm`.

### 4.4 `issuer` must match Keycloak's `KC_HOSTNAME`

RabbitMQ validates the `iss` claim in incoming JWTs against the configured `issuer`.
Keycloak stamps the `iss` field using `KC_HOSTNAME` (the external-facing base URL).

If `KC_HOSTNAME = "https://host:8888/auth"`, then every token contains:
```json
{ "iss": "https://host:8888/auth/realms/cdm" }
```

The `issuer` in `advanced.config.tpl` must match this exactly.  Using an internal
hostname here (`http://keycloak:8080/auth/realms/cdm`) causes token validation to fail
after login.

---

## 5. Keycloak `cdm` realm — RabbitMQ scopes

The `cdm` realm must define **both** the standard OIDC scopes **and** the
RabbitMQ-specific permission scopes.

### Required standard scopes (must exist in realm)

| Scope | Why |
|---|---|
| `openid` | OIDC baseline; RabbitMQ requests `scope=openid profile` during the auth flow |
| `profile` | Standard OIDC profile claims |
| `email` | Standard OIDC email claims |

These are **not** auto-created by Keycloak on realm import.  `realm-cdm.json.tpl`
defines them explicitly.  If they are missing, the login flow shows:
```
ErrorResponse: Invalid scopes: openid profile
```

### RabbitMQ permission scopes

| Scope name | Grants |
|---|---|
| `rabbitmq.tag:administrator` | Full management UI access |
| `rabbitmq.read:*/*` | Read all vhosts/queues |
| `rabbitmq.write:*/*` | Write all vhosts/queues |
| `rabbitmq.configure:*/*` | Configure all vhosts/queues |
| `rabbitmq.tag:monitoring` | Read-only UI access (optional scope) |

All of these must be assigned as **default scopes** on the `rabbitmq-management` client.

---

## 6. Login credentials

| Realm | Username | Password env var | Notes |
|---|---|---|---|
| `cdm` | `cdm-admin` (default) | `KC_ADMIN_PASSWORD` | Has `platform-admin` role → full `rabbitmq.tag:administrator` access |
| `cdm` | `cdm-operator` | `KC_ADMIN_PASSWORD` | Has `platform-operator` role → operator-level access |

> **Correct realm:** The RabbitMQ SSO button redirects to the **`cdm`** realm.

---

## 7. Verifying the setup

### Check that the OIDC discovery endpoint is reachable from the browser

```bash
# In a browser or from the host (not from inside Docker):
curl "${EXTERNAL_URL}/auth/realms/cdm/.well-known/openid-configuration" | jq .issuer
# Must return: "https://<host>/auth/realms/cdm"  (matches KC_HOSTNAME + /auth)
```

### Verify JWT claims after login

```bash
source provider-stack/.env
TOKEN=$(curl -sf -X POST \
  "${EXTERNAL_URL}/auth/realms/cdm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Decode payload (no signature check)
python3 -c "import sys,json,base64; p=sys.argv[1].split('.')[1]; p+='='*(4-len(p)%4); print(json.dumps(json.loads(base64.b64decode(p)), indent=2))" "$TOKEN" \
  | grep -E '"iss"|"aud"|"scope"'
```

Expected output:
```json
"iss": "https://<EXTERNAL_URL_HOST>/auth/realms/cdm",
"aud": ["rabbitmq", "account"],
"scope": "openid profile email rabbitmq.tag:administrator rabbitmq.read:*/* ...",
```

---

## 8. Quick-fix runbook

### RabbitMQ bootstrap.js returns HTTP 500

```bash
# Check the error in the RabbitMQ management log
docker compose -f provider-stack/docker-compose.yml logs rabbitmq | grep -i "case clause\|oauth"
# Look for: no case clause matching <<"sp_initiated">>
# Fix: ensure advanced.config.tpl does NOT contain oauth_initiated_logon_type
docker compose -f provider-stack/docker-compose.yml restart rabbitmq
```

### "ErrorResponse: Invalid scopes: openid profile" on SSO login

```bash
source provider-stack/.env

TOKEN=$(curl -sf -X POST \
  "${EXTERNAL_URL}/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Check what scopes exist in the cdm realm
curl -sf -H "Authorization: Bearer $TOKEN" \
  "${EXTERNAL_URL}/auth/admin/realms/cdm/client-scopes" \
  | python3 -c "import sys,json; [print(s['name']) for s in json.load(sys.stdin)]"
# If openid/profile/email are missing → rebuild/restart Keycloak (realms are re-imported on fresh volume)
# OR create them via REST API (see cdm-keycloak SKILL.md Section 7.6)
```
