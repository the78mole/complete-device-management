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

### step-ca fails with "certificate already exists"

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

**Cause:** `EXTERNAL_URL` or `INFLUX_EXTERNAL_URL` is set to `http://localhost:…` but the
browser is accessing the service via a GitHub Codespaces URL (`*.app.github.dev`).
oauth2-proxy validates redirect URIs against the configured allow-list.

**Fix:** Update `.env` to the full Codespaces URLs:

```dotenv
EXTERNAL_URL=https://<CODESPACE_NAME>-8888.app.github.dev
INFLUX_EXTERNAL_URL=https://<CODESPACE_NAME>-8086.app.github.dev
INFLUX_PROXY_COOKIE_SECURE=true
INFLUX_PROXY_COOKIE_SAMESITE=none
```

Then restart the affected proxies:

```bash
docker compose restart influxdb-proxy caddy
```

---

### InfluxDB shows its own login screen after Keycloak authentication

**Cause:** `oauth2-proxy` proxies to InfluxDB directly without providing an API token.
InfluxDB has its own independent authentication layer and shows a native login form for
unauthenticated requests.

**Fix:** Ensure `OAUTH2_PROXY_UPSTREAMS` in `docker-compose.yml` points to the
`influxdb-token-injector` sidecar, **not** to `influxdb:8086` directly:

```yaml
OAUTH2_PROXY_UPSTREAMS: http://influxdb-token-injector:8087
```

Also verify that the `influxdb-token-injector` container is running:

```bash
docker compose ps influxdb-token-injector
# Should show: running
docker compose logs influxdb-token-injector
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

**Cause:** The `provider` Keycloak realm is missing the standard OIDC client scopes
(`openid`, `profile`, `email`).  These are not auto-created on realm import — they must be
explicitly defined in the realm JSON template.

**Symptom:** After clicking the **Sign in with Keycloak** button, the login flow fails:

```
ErrorResponse: Invalid scopes: openid profile
```

**Fix (permanent — requires Keycloak rebuild):** Ensure `realm-provider.json.tpl` contains
full definitions for `openid`, `profile`, and `email` in its `clientScopes` array and that
these are listed in the `rabbitmq-management` client's `defaultClientScopes`.

**Fix (live — without restarting Keycloak):** Create the scopes via the Admin REST API:

```bash
source provider-stack/.env

TOKEN=$(curl -sf -X POST \
  "${EXTERNAL_URL}/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=${KC_ADMIN_USER}&password=${KC_ADMIN_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

for SCOPE in openid profile email; do
  curl -sf -X POST "${EXTERNAL_URL}/auth/admin/realms/provider/client-scopes" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${SCOPE}\",\"protocol\":\"openid-connect\"}"
  echo "Created: ${SCOPE}"
done
```

Then assign the new scopes as default scopes to the `rabbitmq-management` client in the
Keycloak Admin Console: **Realms → provider → Clients → rabbitmq-management → Client Scopes → Add client scope**.

---

### RabbitMQ SSO: "Unable to get OIDC configuration from …/keycloak:8080"

**Cause:** In RabbitMQ 4.x, `oauth_provider_url` is forwarded directly to the browser for
OIDC discovery.  An internal Docker hostname (`keycloak:8080`) cannot be resolved by the
browser.

**Fix:** Set `oauth_provider_url` to the browser-reachable external URL in
`advanced.config.tpl`:

```erlang
{oauth_provider_url, "EXTERNAL_URL_PLACEHOLDER/auth/realms/provider"}
```

Also ensure the `issuer` in `rabbitmq_auth_backend_oauth2` matches the external URL (because
`KC_HOSTNAME` stamps that URL into the `iss` claim of issued JWTs):

```erlang
{issuer, "EXTERNAL_URL_PLACEHOLDER/auth/realms/provider"}
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

## Getting Further Help

1. Search the [GitHub Discussions](https://github.com/the78mole/complete-device-management/discussions).
2. Check the [GitHub Issues](https://github.com/the78mole/complete-device-management/issues) for known bugs.
3. If you believe you have found a new bug, open one using the [bug report template](https://github.com/the78mole/complete-device-management/issues/new?template=bug_report.yml).
