# OTA Update Workflow

!!! info "Phase 2 — Tenant-Stack"
    hawkBit and RAUC update components are part of the **Tenant-Stack** (Phase 2).
    See [Tenant-Stack Setup](../installation/tenant-stack.md) and
    [Tenant Onboarding](../use-cases/tenant-onboarding.md) for prerequisites.

This page covers the full OTA software lifecycle — from uploading a bundle to monitoring
rollout success across the fleet.

---

## Components Involved

| Component | Role |
|---|---|
| hawkBit | Campaign management, artefact storage, DDI API |
| rauc-hawkbit-updater | Device-side DDI client; triggers RAUC install |
| RAUC | Executes A/B atomic OS or application updates |
| ThingsBoard | Receives OTA status telemetry from devices |
| Grafana | Visualises rollout success rates across the fleet |

---

## Update Types

| Type | Description |
|---|---|
| OS (rootfs) update | Full Yocto rootfs image installed to inactive A/B slot; device reboots |
| Application bundle | RAUC bundle containing only app data; no reboot required (with RAUC app slots) |
| Config update | Small configuration artefact applied by a post-install hook |

---

## Bundle Signing

RAUC requires every OTA bundle to be signed with a trusted certificate whose CA chain
is compiled into the device image (RAUC keyring).

The CDM platform offers two signing approaches depending on security requirements:

### Option A — Manual signing (development / small teams)

Generate a signing key pair, get it signed by the Tenant Sub-CA (`step-ca`), and
keep the private key on a secured local machine:

```bash
# Generate key pair
step crypto keypair rauc-signing.pub rauc-signing.key \
  --kty EC --curve P-384 --no-password --insecure

# Request a code-signing certificate from the Tenant Sub-CA
step ca certificate "My Tenant Code Signing" rauc-signing.crt rauc-signing.key \
  --ca-url https://localhost:19000 \
  --provisioner code-signer \
  --not-after 8760h

# Sign the RAUC bundle
rauc bundle \
  --cert rauc-signing.crt \
  --key rauc-signing.key \
  rootfs-1.1.0.tar.gz \
  cdm-os-1.1.0.raucb
```

### Option B — OpenBao-backed signing (recommended for production)

When the `code-signing` Docker Compose profile is active, the Tenant-Stack runs
[OpenBao](../architecture/key-management.md) as a secrets store.  The code-signing
certificate is issued by the Tenant Sub-CA on first boot and stored in OpenBao KV-v2.
CI/CD pipelines authenticate via AppRole and retrieve the certificate for bundle assembly.

```bash
# Set environment variables (from .env)
OPENBAO_ADDR=http://localhost:18200
OPENBAO_CODESIGN_ROLE_ID=<from .env>
OPENBAO_CODESIGN_SECRET_ID=<from .env>

# Authenticate and get a token
VAULT_TOKEN=$(curl -s --request POST \
  --data "{\"role_id\":\"${OPENBAO_CODESIGN_ROLE_ID}\",\"secret_id\":\"${OPENBAO_CODESIGN_SECRET_ID}\"}" \
  "${OPENBAO_ADDR}/v1/auth/approle/login" | jq -r .auth.client_token)

# Retrieve the code-signing certificate
curl -sH "X-Vault-Token: $VAULT_TOKEN" \
  "${OPENBAO_ADDR}/v1/code-signing/data/cert" \
  | jq -r '.data.data.cert'  > rauc-signing.crt
curl -sH "X-Vault-Token: $VAULT_TOKEN" \
  "${OPENBAO_ADDR}/v1/code-signing/data/cert" \
  | jq -r '.data.data.key'   > rauc-signing.key
curl -sH "X-Vault-Token: $VAULT_TOKEN" \
  "${OPENBAO_ADDR}/v1/code-signing/data/cert" \
  | jq -r '.data.data.ca_chain' > ca-chain.crt

# Sign the RAUC bundle
rauc bundle \
  --cert rauc-signing.crt \
  --key  rauc-signing.key \
  --keyring ca-chain.crt \
  rootfs-1.1.0.tar.gz \
  cdm-os-1.1.0.raucb

# Remove local private key copy
shred -u rauc-signing.key
```

See [Key Management](../architecture/key-management.md) for full setup instructions.

---

## Full Rollout Procedure

### 1. Build and Sign the Bundle

See [Bundle Signing](#bundle-signing) above for key retrieval.

```bash
# Sign the RAUC bundle with the signing certificate
rauc bundle \
  --cert rauc-signing.crt \
  --key rauc-signing.key \
  rootfs-1.1.0.tar.gz \
  cdm-os-1.1.0.raucb
```

### 2. Create a Software Module in hawkBit

Replace `HAWKBIT` with the Tenant-Stack hawkBit URL (e.g. `https://tenant.example.com/hawkbit`):

```bash
HAWKBIT=https://tenant.example.com/hawkbit
# Via hawkBit REST API
curl -X POST $HAWKBIT/rest/v1/softwaremodules \
  -H "Authorization: Basic <base64-creds>" -H "Content-Type: application/json" \
  -d '{"name":"cdm-os","version":"1.1.0","type":"os"}'
```

Upload the bundle:

```bash
curl -X POST "$HAWKBIT/rest/v1/softwaremodules/{id}/artifacts" \
  -H "Authorization: Basic <base64-creds>" -F "file=@cdm-os-1.1.0.raucb"
```

### 3. Create a Distribution Set

```bash
curl -X POST $HAWKBIT/rest/v1/distributionsets \
  -H "Authorization: Basic <base64-creds>" -H "Content-Type: application/json" \
  -d '{"name":"cdm-release-1.1.0","version":"1.1.0","modules":[{"id":<module_id>}]}'
```

### 4. Create a Rollout with Staged Groups

For a staged rollout (canary → 10% → 50% → 100%):

```bash
curl -X POST $HAWKBIT/rest/v1/rollouts \
  -H "Authorization: Basic <base64-creds>" -H "Content-Type: application/json" \
  -d '{
    "name": "rollout-1.1.0",
    "distributionSetId": <ds_id>,
    "targetFilterQuery": "name==device-*",
    "amountGroups": 4,
    "successThreshold": "95",
    "errorThreshold": "5",
    "actionType": "soft"
  }'
```

Start the rollout:

```bash
curl -X POST "http://localhost:8090/rest/v1/rollouts/{rollout_id}/start" -u admin:admin
```

### 5. Device Receives and Applies the Update

The device polls hawkBit every `polling_sleep_time` seconds (configured in `rauc-hawkbit-updater.conf`):

```
[rauc-hawkbit-updater] Checking for deployment action...
[rauc-hawkbit-updater] Action found — downloading artefact...
[rauc-hawkbit-updater] Calling rauc install /tmp/cdm-os-1.1.0.raucb...
[rauc-hawkbit-updater] RAUC install succeeded — marking boot slot B as active...
[rauc-hawkbit-updater] Reporting success to hawkBit...
[system] Rebooting into slot B...
```

### 6. Monitor Rollout Progress

In the hawkBit UI (**Rollout** view), track:

- **Scheduled** → waiting for their group to activate
- **Running** → actively downloading/installing
- **Finished: Success / Error** — success rate must stay above `successThreshold`

In Grafana (**OTA Rollout** dashboard):

- Fleet-wide success rate over time
- P50/P95 download duration
- Error breakdown by error code

---

## Rollback

hawkBit does not automatically roll back devices (RAUC handles that locally). If a device fails to boot after an update:

1. RAUC's boot loader integration (Barebox/U-Boot) automatically falls back to the previously active slot after `max_boot_attempts` failed boots.
2. The device reports back to hawkBit with status `FAILURE`.
3. The hawkBit rollout pauses if error rate exceeds `errorThreshold`.

Manually trigger a rollback by assigning the previous Distribution Set to the affected device.

---

## OTA Status Telemetry

Devices publish OTA status to ThingsBoard after each update:

```json
{
  "sw_version": "1.1.0",
  "rauc_slot": "B",
  "ota_status": "success",
  "ota_error": null
}
```

The ThingsBoard rule chain can trigger an alarm if `ota_status` is `"failure"`.
