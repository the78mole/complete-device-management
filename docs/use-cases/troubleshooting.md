# Troubleshooting

This page collects the most common operational problems and their solutions.

---

## Provider-Stack

### Services fail to start — "port already in use"

```
Error: bind: address already in use (0.0.0.0:8888)
```

**Fix:** Stop the conflicting process or change the port mapping in `.env`:

```bash
# Find the conflicting process
lsof -i :8888
# Or change the port in .env
CADDY_HTTP_PORT=9888
```

---

### ThingsBoard exits immediately after start

**Likely cause:** PostgreSQL is not ready when ThingsBoard starts.

**Fix:**

```bash
docker compose restart thingsboard
# Wait 60–90 seconds — ThingsBoard is slow to initialise
docker compose ps
```

---

### `rabbitmq-cert-init` exits with code 1 — "invalid value for flag '--provisioner'"

**Cause:** The `iot-bridge` JWK provisioner does not exist in step-ca yet.  This happens
when step-ca was initialised without running the provisioner setup script (e.g. after
wiping `step-ca-data` and restarting without rebuilding the image).

**Symptoms in logs:**

```
>>> Requesting RabbitMQ server certificate from step-ca...
invalid value 'iot-bridge' for flag '--provisioner'
```

**Fix:** Trigger the provisioner init script manually:

```bash
cd provider-stack
docker compose exec step-ca /usr/local/bin/init-provisioners.sh
# Then restart the cert-init services:
docker compose up -d rabbitmq-cert-init
```

!!! note "Automatic on every start (since March 2026)"
    The `step-ca` entrypoint now calls `init-provisioners.sh` automatically in the
    background before marking the container healthy.  This error should no longer occur
    on fresh deployments.

---

### `rabbitmq-cert-init` exits with code 1 — "requested duration … more than the authorized maximum"

**Cause:** The `iot-bridge` provisioner exists but was created without raising the
maximum certificate duration (default: 24 h).  `rabbitmq-cert-init` requests 8760 h (1 year).

**Fix:** Update the provisioner duration limit:

```bash
cd provider-stack
docker compose exec step-ca sh -c "
  step ca provisioner update iot-bridge \
    --x509-max-dur 8760h \
    --admin-subject step \
    --admin-provisioner cdm-admin@cdm.local \
    --admin-password-file /run/secrets/step-ca-password"
# Then retry:
docker compose up -d rabbitmq-cert-init
```

---



**Likely cause:** The `step-ca-data` volume already contains a CA from a previous run with a different password.

**Fix (destructive — deletes the CA):**

```bash
# Provider Root CA
docker compose -f provider-stack/docker-compose.yml down
docker volume rm provider-stack_step-ca-data
docker compose -f provider-stack/docker-compose.yml up -d
```

!!! warning
    This invalidates all previously issued certificates. Re-enroll all devices.

---

### iot-bridge-api returns `503` on enrollment

**Causes:**

1. step-ca is not healthy.
2. `STEP_CA_URL` is wrong.
3. `STEP_CA_VERIFY_TLS=true` but the CA certificate is not trusted.

**Fix:**

```bash
# Check step-ca health
curl -k https://localhost:9000/health
# Should return: {"status":"ok"}

# Check env
docker compose exec iot-bridge-api env | grep STEP_CA
```

If `STEP_CA_VERIFY_TLS=true`, set it to `false` for local dev, or mount the Root CA cert and point `SSL_CERT_FILE` to it.

---

### Keycloak login page shows no CSS — black unstyled page

**Cause:** `KC_HOSTNAME` is set to the bare origin (e.g. `https://host:8888`) without the `/auth` path suffix.  When `KC_HTTP_RELATIVE_PATH=/auth` is configured, Keycloak uses `KC_HOSTNAME` as the base for all generated URLs.  Without the path prefix, static assets are served at `/resources/…` (404) instead of `/auth/resources/…`, and form actions also lose the prefix.

**Fix:** Ensure `KC_HOSTNAME` in `docker-compose.yml` includes `/auth`:

```yaml
# provider-stack/docker-compose.yml  — keycloak service
KC_HOSTNAME: "${EXTERNAL_URL:-http://localhost:8888}/auth"
```

Rebuild and restart after the change:

```bash
cd provider-stack
docker compose build keycloak
docker compose up -d keycloak
```

---

### oauth2-proxy "Rejecting invalid redirect" / "domain / port not in whitelist"

**Cause:** `EXTERNAL_URL` is set to `http://localhost:...` but the browser is accessing
the service via a GitHub Codespaces URL (`*.app.github.dev`).
oauth2-proxy validates redirect URIs against the configured allow-list.

**Fix:** Update `.env` to the full Codespaces URL:

```dotenv
EXTERNAL_URL=https://<CODESPACE_NAME>-8888.app.github.dev
```

Then restart Caddy:

```bash
docker compose restart caddy
```

---

### TimescaleDB connection refused / Telegraf write errors

**Cause:** Telegraf can't reach TimescaleDB, or user credentials are wrong.

**Fix:** Verify TimescaleDB is healthy:

```bash
docker compose ps timescaledb
# Should show: running (healthy)
docker compose logs timescaledb | tail -20
```

Verify Telegraf credentials:

```bash
docker compose exec timescaledb psql -U postgres -d cdm -c "\\du"
# Should list telegraf and grafana users
```

If credentials appear correct but Telegraf still fails:

```bash
docker compose restart telegraf
docker compose logs telegraf | grep -i error
```

---

### RabbitMQ `bootstrap.js` returns HTTP 500

**Error in browser console:**

```
GET /rabbitmq/js/bootstrap.js 500 Internal Server Error
```

**Error in RabbitMQ logs:**

```
no case clause matching <<"sp_initiated">>
```

**Cause:** The `oauth_initiated_logon_type` setting was removed in RabbitMQ 4.0.  If
`advanced.config.tpl` still contains `{oauth_initiated_logon_type, <<"sp_initiated">>}`,
the Erlang management plugin crashes on any request.

**Fix:** Remove the line from `provider-stack/rabbitmq/advanced.config.tpl` and restart:

```bash
# Verify the option is gone
grep -n "oauth_initiated_logon_type" provider-stack/rabbitmq/advanced.config.tpl
# Should return nothing

docker compose restart rabbitmq
```

---

### RabbitMQ SSO: "ErrorResponse: Invalid scopes: openid profile"

**Cause:** The `cdm` Keycloak realm is missing the standard OIDC client scopes
(`openid`, `profile`, `email`).  These are not auto-created on realm import — they must be
explicitly defined in the realm JSON template.

**Symptom:** After clicking the **Sign in with Keycloak** button, the login flow fails:

```
ErrorResponse: Invalid scopes: openid profile
```

**Fix (permanent — requires Keycloak rebuild):** Ensure `realm-cdm.json.tpl` contains
full definitions for `profile`, `email`, `roles`, and `web-origins` in its `clientScopes`
array and that these are listed in `defaultDefaultClientScopes`.

**Fix (live — without restarting Keycloak):** Create the scopes via the Admin REST API:

```bash
source provider-stack/.env

TOKEN=$(curl -sf -X POST \
  "${EXTERNAL_URL}/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

for SCOPE in openid profile email; do
  curl -sf -X POST "${EXTERNAL_URL}/auth/admin/realms/cdm/client-scopes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${SCOPE}\",\"protocol\":\"openid-connect\"}"
  echo "Created: ${SCOPE}"
done
```

Then assign the new scopes as default scopes to the `rabbitmq-management` client in the
Keycloak Admin Console: **Realms → cdm → Clients → rabbitmq-management → Client Scopes → Add client scope**.

---

### RabbitMQ SSO: "Unable to get OIDC configuration from …/keycloak:8080"

**Cause:** In RabbitMQ 4.x, `oauth_provider_url` is forwarded directly to the browser for
OIDC discovery.  An internal Docker hostname (`keycloak:8080`) cannot be resolved by the
browser.

**Fix:** Set `oauth_provider_url` to the browser-reachable external URL in
`advanced.config.tpl`:

```erlang
{oauth_provider_url, "EXTERNAL_URL_PLACEHOLDER/auth/realms/cdm"}
```

Also ensure the `issuer` in `rabbitmq_auth_backend_oauth2` matches the external URL (because
`KC_HOSTNAME` stamps that URL into the `iss` claim of issued JWTs):

```erlang
{issuer, "EXTERNAL_URL_PLACEHOLDER/auth/realms/cdm"}
```

The `EXTERNAL_URL_PLACEHOLDER` is replaced with `${EXTERNAL_URL}` by the RabbitMQ
`docker-entrypoint.sh` at container start.

---

**Cause:** Services use the internal Docker hostname `provider-keycloak` (or `tenant-keycloak`), but the redirect URI was set to `localhost`.

**Fix:** Update `Valid Redirect URIs` in each Keycloak client to use the external Caddy hostname, and ensure `KC_HOSTNAME` in `.env` matches the externally reachable name.

---

## Device Stack

### bootstrap exits with code 1 — "curl: (6) Could not resolve host"

**Cause:** `TENANT_API_URL` points to `localhost` which resolves to the container itself.

**Fix:** Use the Docker host IP or the service name:

```bash
# On Linux (Docker host IP from inside a container)
TENANT_API_URL=http://172.17.0.1:8000
# Or use host.docker.internal (macOS/Windows)
TENANT_API_URL=http://host.docker.internal:8000
```

---

### bootstrap is not idempotent — re-enrolls on every start

**Cause:** The `/certs/enrolled` flag file is not persisted (volume not mounted).

**Fix:** Ensure the `device-certs` volume is declared and mounted in `docker-compose.yml`.

---

### mqtt-client cannot connect — "SSL handshake failed"

**Causes:**

1. `ca-chain.crt` does not match the ThingsBoard MQTT TLS certificate.
2. ThingsBoard MQTT TLS is not enabled.

**Fix:**

```bash
# Verify the cert chain
openssl verify -CAfile /certs/ca-chain.crt /certs/device.crt

# Test the TLS connection manually
openssl s_client -connect localhost:8883 -CAfile /certs/ca-chain.crt
```

---

### WireGuard tunnel not establishing — "RTNETLINK answers: Operation not permitted"

**Cause:** WireGuard requires the `NET_ADMIN` Linux capability.

**Fix:** Add capability to the wireguard-client service in `docker-compose.yml`:

```yaml
cap_add:
  - NET_ADMIN
  - SYS_MODULE
```

---

## Terminal Proxy

### `401 Unauthorized` — "jwt audience invalid"

**Fix:** Ensure `KEYCLOAK_AUDIENCE` in terminal-proxy matches the `aud` claim in your Keycloak-issued JWT. Typically this is the client ID: `thingsboard`.

---

### `404 Not Found` — "device not found in peers DB"

**Fix:** Verify the device is enrolled and `cdm_peers.json` contains the device (run in the Tenant-Stack directory):

```bash
docker compose exec terminal-proxy cat /wg-config/cdm_peers.json
```

If missing, re-run the device enrollment.

---

### WebSocket connects but terminal immediately closes

**Cause:** `ttyd` is not running on the device, or it is bound to the wrong interface.

**Fix:** On the device:

```bash
systemctl status ttyd
# If failed:
journalctl -u ttyd -n 30
# Check the bind address — must be the WireGuard interface IP, not 0.0.0.0
```

---

## Stack Communication

### Tenant-Stack cannot publish to Provider RabbitMQ

**Cause:** RabbitMQ vHost, EXTERNAL user, or mTLS certificates not yet provisioned
on the Provider-Stack.

**Fix:**

```bash
# Check that the tenant vHost and EXTERNAL user exist on the Provider-Stack
docker compose -f provider-stack/docker-compose.yml exec rabbitmq \
  rabbitmqctl list_vhosts
docker compose -f provider-stack/docker-compose.yml exec rabbitmq \
  rabbitmqctl list_users
# Expected user: <tenant-id>-mqtt-bridge

# Verify the MQTT bridge client certificate on the Tenant-Stack
docker compose exec ${TENANT_ID}-step-ca \
  step certificate inspect /home/step/mqtt-bridge/client.crt

# Check the MQTTS port is reachable
docker compose -f provider-stack/docker-compose.yml exec rabbitmq \
  rabbitmq-diagnostics listeners
# Should show: Interface: [::], port: 8883, Protocol: mqtt/ssl
```

If the JOIN workflow was completed before the mTLS changes were deployed, re-approve
the JOIN request to issue a new MQTT bridge certificate.

### Tenant Keycloak federation login fails

**Cause:** Provider Keycloak OIDC client for the Tenant-Stack is not yet configured, or client secret is wrong.

**Fix:** Re-run the JOIN workflow step from [Tenant Onboarding](../use-cases/tenant-onboarding.md),
or update the client secret in Provider Keycloak → Realm `cdm` → Clients → `<tenant-id>-idp`.

---

## Full Reset: "Green-Field" Test

Use this procedure to wipe all persistent state and restart the Provider-Stack completely
from scratch — as if it were deployed for the first time.

!!! danger "Destructive — all data will be lost"
    This procedure deletes **all Docker volumes** for the stack:
    - Root CA and all issued certificates
    - OpenBao keys and secrets (new Transit keys will be generated)
    - Keycloak database (all realms, clients, and users)
    - TimescaleDB data (all metrics)
    - RabbitMQ configuration (all vhosts, users, queues)

    Any connected Tenant-Stacks and enrolled devices will need to be re-enrolled.

### Reset Provider-Stack

```bash
cd provider-stack

# 1. Stop and remove all containers + volumes
docker compose down -v

# 2. (Optional) Remove built images to force a full rebuild
docker compose rm -sf
docker images | grep provider-stack | awk '{print $3}' | xargs -r docker rmi -f

# 3. Reset the .env back to minimal defaults
#    (preserve your passwords, but clear auto-generated values)
sed -i \
  -e 's/^STEP_CA_FINGERPRINT=.*/STEP_CA_FINGERPRINT=/' \
  -e 's/^OPENBAO_STEP_CA_ROLE_ID=.*/OPENBAO_STEP_CA_ROLE_ID=/' \
  -e 's/^OPENBAO_STEP_CA_SECRET_ID=.*/OPENBAO_STEP_CA_SECRET_ID=/' \
  -e 's/^GRAFANA_OIDC_SECRET=.*/GRAFANA_OIDC_SECRET=changeme/' \
  -e 's/^BRIDGE_OIDC_SECRET=.*/BRIDGE_OIDC_SECRET=changeme/' \
  -e 's/^PGADMIN_OIDC_SECRET=.*/PGADMIN_OIDC_SECRET=changeme/' \
  -e 's/^RABBITMQ_MANAGEMENT_OIDC_SECRET=.*/RABBITMQ_MANAGEMENT_OIDC_SECRET=changeme/' \
  .env

# 4. Start fresh
docker compose up -d

# 5. Wait for all services to be healthy (~60–90 s)
docker compose ps

# 6. Copy the new STEP_CA_FINGERPRINT from step-ca logs
docker compose logs step-ca | grep 'Root CA fingerprint'
# → Update STEP_CA_FINGERPRINT in .env

# 7. Copy the new OpenBao AppRole credentials
docker compose logs openbao | grep 'OPENBAO_STEP_CA'
# → Update OPENBAO_STEP_CA_ROLE_ID and OPENBAO_STEP_CA_SECRET_ID in .env

# 8. Retrieve fresh Keycloak OIDC secrets and update .env
#    (see Installation → Provider-Stack → A6)
```

### Reset a Tenant-Stack (without touching the Provider)

```bash
cd tenant-stack

# Stop and remove all containers + volumes for this tenant
docker compose down -v

# Clear auto-generated values in .env
sed -i \
  -e 's/^OPENBAO_TENANT_ROLE_ID=.*/OPENBAO_TENANT_ROLE_ID=/' \
  -e 's/^OPENBAO_TENANT_SECRET_ID=.*/OPENBAO_TENANT_SECRET_ID=/' \
  .env

# Restart — the JOIN workflow will be required again
docker compose up -d
docker compose exec ${TENANT_ID}-step-ca /usr/local/bin/init-sub-ca.sh
```

### Verify the fresh stack

```bash
cd provider-stack

# All long-running services must be healthy or running
docker compose ps

# One-shot init containers must have exited 0
docker compose logs rabbitmq-cert-init | tail -5
# Expected last line: >>> cert-init complete.

docker compose logs mqtt-certs-init | tail -5
# Expected last line: >>> mqtt-certs-init complete.

# step-ca health
curl -sk https://localhost:9000/health
# Expected: {"status":"ok"}

# Provisioners present
docker compose exec step-ca step ca provisioner list | grep '"name"'
# Expected: cdm-admin@cdm.local, acme, iot-bridge, tenant-sub-ca-signer
```

---

## Getting Further Help

1. Search the [GitHub Discussions](https://github.com/the78mole/complete-device-management/discussions).
2. Check the [GitHub Issues](https://github.com/the78mole/complete-device-management/issues) for known bugs.
3. If you believe you have found a new bug, open one using the [bug report template](https://github.com/the78mole/complete-device-management/issues/new?template=bug_report.yml).
