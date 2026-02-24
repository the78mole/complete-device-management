# Security Incident Response

This use case covers how to respond to security incidents — compromised devices, leaked credentials, and suspicious activity.

---

## Scenario 1 — Compromised Device Certificate

**Trigger:** A device is physically stolen or its private key is extracted.

### Response Steps

#### 1. Revoke the Certificate at Tenant Sub-CA

```bash
# Against the Tenant step-ca Sub-CA
step ca revoke \
  --cert /path/to/device-001.crt \
  --ca-url https://tenant.example.com/pki \
  --root root_ca.crt
```

If you do not have the certificate file, revoke by serial number:

```bash
step ca revoke <serial-number> \
  --ca-url https://tenant.example.com/pki \
  --root root_ca.crt
```

#### 1b. Escalation: Compromise of the Tenant Sub-CA itself

If the Sub-CA private key is compromised, revoke the Sub-CA certificate at the Provider Root CA:

```bash
# Against the Provider step-ca (Root/Intermediate CA)
step ca revoke <sub-ca-serial> \
  --ca-url https://provider.example.com/pki \
  --root provider_root_ca.crt
```

Then re-issue a new Sub-CA for the tenant and re-enroll all tenant devices.

#### 2. Remove the WireGuard Peer (Tenant-Stack)

```bash
# On the Tenant-Stack host
# Find the device's public key
docker compose exec tenant-iot-bridge-api cat /wg-config/cdm_peers.json | grep device-001 -A3

# Remove from WireGuard interface
wg set wg0 peer <compromised-device-public-key> remove
wg-quick save wg0

# Remove from peers JSON
docker compose exec tenant-iot-bridge-api \
  python3 -c "
import json
with open('/wg-config/cdm_peers.json') as f: data = json.load(f)
data['peers'] = {k:v for k,v in data['peers'].items() if k != 'device-001'}
with open('/wg-config/cdm_peers.json','w') as f: json.dump(data, f)
"
```

#### 3. Delete the Device from ThingsBoard (Tenant-Stack)

```bash
curl -X DELETE https://tenant.example.com:9090/api/device/<device-id> \
  -H "Authorization: Bearer <admin-jwt>"
```

#### 4. Delete the Target from hawkBit (Tenant-Stack)

```bash
curl -X DELETE https://tenant.example.com/hawkbit/rest/v1/targets/device-001 \
  -H "Authorization: Basic <base64-creds>"
```

#### 5. Issue a New Certificate for the Replacement Device

Follow the [Device Provisioning Workflow](../workflows/device-provisioning.md) with a new `DEVICE_ID`.

---

## Scenario 2 — Leaked InfluxDB Token

**Trigger:** An InfluxDB write token is accidentally exposed in logs or a git commit.

### Response Steps

1. Log in to Tenant InfluxDB (`https://tenant.example.com:8086`) or Provider InfluxDB (`https://provider.example.com:8086`).
2. Go to **Load Data → API Tokens**.
3. Find the compromised token and click **Delete**.
4. Create a new token with the same permissions.
5. Update `INFLUXDB_TOKEN` in the relevant `.env` and restart Telegraf on all devices.

---

## Scenario 3 — Suspicious MQTT Traffic

**Trigger:** A device is sending unexpected telemetry topics or unusual payloads.

### Investigation

1. In ThingsBoard, open the device → **Latest Telemetry** — check for unexpected keys.
2. Enable Rule Chain debug mode to inspect raw MQTT messages.
3. If the behaviour is confirmed malicious, revoke the certificate (Scenario 1).

### Prevention

- Use ThingsBoard MQTT topic filtering to reject unexpected topics at the broker level.
- Enable ThingsBoard's rate limiting per device to detect flooding attacks.

---

## Scenario 4 — Keycloak Admin Credential Compromise

**Trigger:** The Keycloak admin password is leaked.

### Response Steps

1. **Immediately** change the admin password via the Keycloak admin CLI (run in the
   affected stack — provider-stack or tenant-stack directory):
   ```bash
   docker compose exec keycloak \
     /opt/keycloak/bin/kcadm.sh set-password \
     --target-realm master --username admin --new-password <new-pw>
   ```
2. Rotate all OIDC client secrets — see [IAM Architecture](../architecture/iam.md).
3. Invalidate all active sessions in the `cdm` realm: **Realm Settings → Sessions → Logout all**.
4. Audit the Keycloak event log for unauthorised actions: **Events → Admin Events**.
5. If the Provider Keycloak admin is compromised, also rotate all OIDC federation client
   secrets used by Tenant Keycloak instances.

---

## Audit Trail

All security-relevant events are logged in:

| Source | How to Access |
|---|---|
| step-ca certificate events | `docker compose logs step-ca` (provider- or tenant-stack) |
| Keycloak admin events | Keycloak UI → **Events → Admin Events** |
| ThingsBoard device events | ThingsBoard UI (Tenant-Stack) → Device → **Audit Log** |
| iot-bridge-api enrollment log | `docker compose logs tenant-iot-bridge-api` |
| WireGuard connection log | `docker compose logs tenant-wireguard` |

For production, forward all logs to a SIEM (e.g. Grafana Loki, OpenSearch, Splunk) for long-term retention and alerting.
