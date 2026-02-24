# Security Incident Response

This use case covers how to respond to security incidents — compromised devices, leaked credentials, and suspicious activity.

---

## Scenario 1 — Compromised Device Certificate

**Trigger:** A device is physically stolen or its private key is extracted.

### Response Steps

#### 1. Revoke the Certificate Immediately

```bash
# From a workstation that trusts the step-ca root
step ca revoke \
  --cert /path/to/device-001.crt \
  --ca-url https://your-step-ca:9000 \
  --root root_ca.crt
```

If you do not have the certificate file, revoke by serial number:

```bash
step ca revoke <serial-number> \
  --ca-url https://your-step-ca:9000 \
  --root root_ca.crt
```

#### 2. Remove the WireGuard Peer

```bash
# On the WireGuard server
wg set wg0 peer <compromised-device-public-key> remove
wg-quick save wg0

# Remove from cdm_peers.json (in the wg-data volume)
docker compose exec iot-bridge-api \
  python3 -c "
import json
with open('/wg-config/cdm_peers.json') as f: data = json.load(f)
data['peers'] = {k:v for k,v in data['peers'].items() if k != 'device-001'}
with open('/wg-config/cdm_peers.json','w') as f: json.dump(data, f)
"
```

#### 3. Delete the Device from ThingsBoard

```bash
curl -X DELETE http://localhost:8080/api/device/<device-id> \
  -H "Authorization: Bearer <admin-jwt>"
```

#### 4. Delete the Target from hawkBit

```bash
curl -X DELETE http://localhost:8090/rest/v1/targets/device-001 \
  -u admin:admin
```

#### 5. Issue a New Certificate for the Replacement Device

Follow the [Device Provisioning Workflow](../workflows/device-provisioning.md) with a new `DEVICE_ID`.

---

## Scenario 2 — Leaked InfluxDB Token

**Trigger:** An InfluxDB write token is accidentally exposed in logs or a git commit.

### Response Steps

1. Log in to InfluxDB (http://localhost:8086).
2. Go to **Load Data → API Tokens**.
3. Find the compromised token and click **Delete**.
4. Create a new token with the same permissions.
5. Update `INFLUXDB_TOKEN` in `.env` and restart Telegraf on all devices.

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

1. **Immediately** change the admin password via the Keycloak admin CLI:
   ```bash
   docker compose exec keycloak \
     /opt/keycloak/bin/kcadm.sh set-password \
     --target-realm master --username admin --new-password <new-pw>
   ```
2. Rotate all OIDC client secrets (ThingsBoard, hawkBit, Grafana) — see [IAM Architecture](../architecture/iam.md#updating-client-secrets).
3. Invalidate all active sessions in the `cdm` realm: **Realm Settings → Sessions → Logout all**.
4. Audit the Keycloak event log for unauthorised actions: **Events → Admin Events**.

---

## Audit Trail

All security-relevant events are logged in:

| Source | How to Access |
|---|---|
| step-ca certificate events | `docker compose logs step-ca` |
| Keycloak admin events | Keycloak UI → **Events → Admin Events** |
| ThingsBoard device events | ThingsBoard UI → Device → **Audit Log** |
| iot-bridge-api enrollment log | `docker compose logs iot-bridge-api` |
| WireGuard connection log | `docker compose logs wireguard` |

For production, forward all logs to a SIEM (e.g. Grafana Loki, OpenSearch, Splunk) for long-term retention and alerting.
