# Troubleshooting

This page collects the most common operational problems and their solutions.

---

## Cloud Infrastructure

### Services fail to start — "port already in use"

```
Error: bind: address already in use (0.0.0.0:8080)
```

**Fix:** Stop the conflicting process or change the port mapping in `.env`:

```bash
# Find the conflicting process
lsof -i :8080
# Or change the port in .env
TB_HTTP_PORT=8081
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
docker compose down
docker volume rm cloud-infrastructure_step-ca-data
docker compose up -d
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

### Keycloak returns `Connection refused` from ThingsBoard/hawkBit

**Cause:** Services use the internal Docker hostname `keycloak`, but the redirect URI was set to `localhost`.

**Fix:** Update `Valid Redirect URIs` in each Keycloak client to use the internal hostname, and ensure `KC_HOSTNAME` in `.env` matches the externally reachable name.

---

## Device Stack

### bootstrap exits with code 1 — "curl: (6) Could not resolve host"

**Cause:** `BRIDGE_API_URL` points to `localhost` which resolves to the container itself.

**Fix:** Use the Docker host IP or the service name:

```bash
# On Linux (Docker host IP from inside a container)
BRIDGE_API_URL=http://172.17.0.1:8000
# Or use host.docker.internal (macOS/Windows)
BRIDGE_API_URL=http://host.docker.internal:8000
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

**Fix:** Verify the device is enrolled and `cdm_peers.json` contains the device:

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

## Getting Further Help

1. Search the [GitHub Discussions](https://github.com/the78mole/complete-device-management/discussions).
2. Check the [GitHub Issues](https://github.com/the78mole/complete-device-management/issues) for known bugs.
3. If you believe you have found a new bug, open one using the [bug report template](https://github.com/the78mole/complete-device-management/issues/new?template=bug_report.yml).
