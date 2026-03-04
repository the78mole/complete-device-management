# CDM Skill — step-ca PKI (Provider Root CA & Tenant Sub-CA)

This document covers the **smallstep step-ca** PKI used in CDM: its two-tier trust
hierarchy, first-boot initialisation, certificate export, and common operational procedures.

---

## 1. Trust hierarchy

```
Root CA              (Provider-Stack · self-signed · 10-year validity)
  └── Intermediate CA      (Provider-Stack · online · 5-year validity)
        ├── Provider Service Certs   (serverAuth + clientAuth · 1-year)
        └── Tenant Issuing Sub-CA    (Tenant-Stack · per-tenant · 2-year)  ×N
              ├── Tenant Service Certs  (serverAuth + clientAuth · 1-year)
              └── Device Certs          (clientAuth only · configurable TTL)
```

**Provider-Stack** hosts the Root CA and the Intermediate CA (both run in a single
`step-ca` container).  It is the trust anchor for the entire platform.

**Tenant-Stack** hosts one Issuing Sub-CA per tenant.  The Sub-CA private key is generated
locally and **never leaves the Tenant-Stack**.  Only the CSR is sent to the Provider for
signing during the [JOIN workflow](../../docs/workflows/device-provisioning.md).

> **Root CA key in production:** After the Intermediate CA has been issued, export the Root
> CA private key from the container, store it offline (HSM or air-gapped vault), and remove
> it from the `step-ca-data` Docker volume.  Only the Intermediate CA needs to remain online.

---

## 2. Files and directories

### Provider-Stack

| Path | Purpose |
|---|---|
| `provider-stack/step-ca/Dockerfile` | Image build — copies templates + init script |
| `provider-stack/step-ca/init-provisioners.sh` | Run-once init: adds `iot-bridge` and `tenant-sub-ca-signer` provisioners |
| `provider-stack/step-ca/password.txt` | Docker secret — used for Root CA key encryption on first boot |
| `provider-stack/step-ca/templates/device-leaf.tpl` | X.509 template for device leaf certs |
| `provider-stack/step-ca/templates/service-leaf.tpl` | X.509 template for service certs |
| `provider-stack/step-ca/templates/tenant-sub-ca.tpl` | X.509 template for Tenant Sub-CA signing |

### Tenant-Stack

| Path | Purpose |
|---|---|
| `tenant-stack/step-ca/Dockerfile` | Image build — copies templates + init script |
| `tenant-stack/step-ca/init-sub-ca.sh` | Run-once init: JOIN workflow + JWK provisioner setup |
| `tenant-stack/step-ca/password.txt` | Docker secret — Sub-CA key encryption |
| `tenant-stack/step-ca/templates/device-leaf.tpl` | Device leaf cert template |
| `tenant-stack/step-ca/templates/service-leaf.tpl` | Service cert template |

### Runtime data (Docker volume `step-ca-data` → `/home/step`)

| File inside container | Contents |
|---|---|
| `/home/step/certs/root_ca.crt` | Root CA PEM certificate |
| `/home/step/certs/intermediate_ca.crt` | Intermediate CA PEM certificate |
| `/home/step/secrets/intermediate_ca_key` | Intermediate CA private key (encrypted) |
| `/home/step/config/ca.json` | step-ca runtime configuration |

---

## 3. Environment variables

### Provider-Stack (`provider-stack/docker-compose.yml`)

| Variable | Default | Purpose |
|---|---|---|
| `DOCKER_STEPCA_INIT_NAME` | `CDM Root CA` | CA display name stamped into the Root cert CN |
| `DOCKER_STEPCA_INIT_DNS_NAMES` | `step-ca,localhost` | SAN DNS names for the CA server TLS cert |
| `DOCKER_STEPCA_INIT_PROVISIONER_NAME` | `cdm-admin@cdm.local` | Name of the bootstrap admin JWK provisioner |
| `DOCKER_STEPCA_INIT_ACME` | `true` | Enable ACME provisioner (used by Caddy for auto-TLS) |
| `DOCKER_STEPCA_INIT_REMOTE_MANAGEMENT` | `true` | Enable Admin API for remote provisioner management |
| `STEP_CA_PROVISIONER_NAME` | `iot-bridge` | Name of the leaf-cert JWK provisioner |
| `STEP_CA_PROVISIONER_PASSWORD` | — | Password for the `iot-bridge` JWK provisioner key |
| `STEP_CA_SUB_CA_PROVISIONER` | `tenant-sub-ca-signer` | Name of the Sub-CA signer provisioner |
| `STEP_CA_SUB_CA_PASSWORD` | — | Password for the `tenant-sub-ca-signer` JWK provisioner key |
| `STEP_CA_FINGERPRINT` | — | Root CA fingerprint — exported to `.env` after first boot for use by Tenant-Stacks |

### Tenant-Stack (`tenant-stack/docker-compose.yml`)

| Variable | Default | Purpose |
|---|---|---|
| `DOCKER_STEPCA_INIT_NAME` | `Tenant Sub-CA` | Sub-CA display name |
| `STEP_CA_PROVIDER_URL` | — | Provider step-ca URL (e.g. `https://provider:9000`); left blank for standalone dev |
| `STEP_CA_PROVIDER_FINGERPRINT` | — | Provider Root CA fingerprint (value of `STEP_CA_FINGERPRINT` from Provider-Stack `.env`) |
| `PROVIDER_API_URL` | — | Provider IoT Bridge API URL for the JOIN workflow |
| `TENANT_ID` | `tenant` | Tenant slug — becomes the Sub-CA container name prefix |
| `TENANT_DISPLAY_NAME` | `Tenant <TENANT_ID>` | Human-readable name stamped into the Sub-CA CN |

---

## 4. Provisioners

### Provider-Stack provisioners

| Name | Type | Purpose |
|---|---|---|
| `cdm-admin@cdm.local` | JWK (bootstrap) | Admin provisioner created by `DOCKER_STEPCA_INIT`; used internally by `init-provisioners.sh` |
| `iot-bridge` | JWK | Signs leaf device and service certificates |
| `tenant-sub-ca-signer` | JWK | Signs Tenant Sub-CA CSRs (`isCA=true`, `maxPathLen=0`) |
| `acme` | ACME | Auto-renews TLS certs for Provider-Stack services (Caddy) |

### Tenant-Stack provisioners

| Name | Type | Purpose |
|---|---|---|
| `tenant-admin@cdm.local` | JWK (bootstrap) | Admin provisioner |
| `iot-bridge` | JWK | Signs device leaf certs issued via the IoT Bridge API |
| `acme` | ACME | Auto-renews service TLS certs |

---

## 5. Certificate templates

### Device leaf (`templates/device-leaf.tpl`)

```json
{
    "subject": {
        "commonName": "{{ .Subject.CommonName }}",
        "organization": ["CDM IoT Platform"],
        "organizationalUnit": ["Devices"]
    },
    "sans": "{{ .SANs }}",
    "keyUsage": ["digitalSignature"],
    "extKeyUsage": ["clientAuth"],
    "basicConstraints": { "isCA": false }
}
```

Device certs carry **`clientAuth` only** — they cannot act as TLS servers.

### Service leaf (`templates/service-leaf.tpl`)

```json
{
    "subject": {
        "commonName": "{{ .Subject.CommonName }}",
        "organization": ["CDM IoT Platform"],
        "organizationalUnit": ["Services"]
    },
    "sans": "{{ .SANs }}",
    "keyUsage": ["digitalSignature", "keyEncipherment"],
    "extKeyUsage": ["serverAuth", "clientAuth"],
    "basicConstraints": { "isCA": false }
}
```

### Tenant Sub-CA signer (`templates/tenant-sub-ca.tpl`)

```json
{
    "subject": "{{ toJson .Subject }}",
    "keyUsage": ["certSign", "crlSign"],
    "basicConstraints": {
        "isCA": true,
        "maxPathLen": 0
    }
}
```

`maxPathLen: 0` means the Sub-CA can only sign leaf certificates — it cannot sign
further intermediate CAs.

---

## 6. First-boot initialisation

### Provider-Stack — automatic + manual

**Automatic (every container start):** When `step-ca-data` volume is empty, the
`DOCKER_STEPCA_INIT_*` environment variables trigger automatic generation of:
- Root CA key + self-signed certificate
- Intermediate CA key + certificate signed by Root CA
- Initial bootstrap `cdm-admin@cdm.local` JWK provisioner
- ACME provisioner

**Manual (run once after first healthy start):** Add the IoT Bridge and Sub-CA provisioners:

```bash
cd provider-stack
docker compose exec step-ca /usr/local/bin/init-provisioners.sh
```

The script outputs the Root CA fingerprint — save it as `STEP_CA_FINGERPRINT` in `.env`.

### Tenant-Stack — manual JOIN workflow

```bash
cd tenant-stack
docker compose exec ${TENANT_ID}-step-ca /usr/local/bin/init-sub-ca.sh
```

`init-sub-ca.sh` performs:
1. Generates Tenant Sub-CA key pair + CSR locally
2. Generates MQTT bridge client key + CSR
3. Submits a JOIN request to the Provider IoT Bridge API (`PROVIDER_API_URL`)
4. Polls until a Provider Admin approves the request
5. Installs the signed Sub-CA cert (replaces the self-signed boot cert)
6. Adds the `iot-bridge` JWK provisioner for device signing
7. Registers Provider Keycloak as an Identity Provider in the Tenant Keycloak realm

---

## 7. Extracting certificates

All commands run from the respective stack directory.

### Root CA fingerprint (needed by Tenant-Stacks and devices)

```bash
cd provider-stack
docker compose exec step-ca step certificate fingerprint /home/step/certs/root_ca.crt
```

Save the output as `STEP_CA_FINGERPRINT` in `provider-stack/.env` and in every
Tenant-Stack and Device-Stack `.env`.

### Export Root CA PEM

```bash
cd provider-stack

# Method 1 — via step-ca API (recommended; validates the CA is healthy)
docker compose exec step-ca step ca root /tmp/root_ca.crt
docker compose cp step-ca:/tmp/root_ca.crt ./root_ca.crt

# Method 2 — directly from the volume
docker compose cp step-ca:/home/step/certs/root_ca.crt ./root_ca.crt
```

### Export Intermediate CA PEM

```bash
cd provider-stack
docker compose cp step-ca:/home/step/certs/intermediate_ca.crt ./intermediate_ca.crt
```

### Build the full CA chain (Root + Intermediate)

```bash
cat intermediate_ca.crt root_ca.crt > ca-chain.crt
```

The chain file is required by devices and services that need to validate the full path.

### Export a Tenant Sub-CA certificate

```bash
cd tenant-stack
docker compose cp step-ca:/home/step/certs/intermediate_ca.crt ./${TENANT_ID}-sub-ca.crt

# Verify it was signed by the Provider Intermediate CA
step certificate verify ${TENANT_ID}-sub-ca.crt --roots intermediate_ca.crt
```

---

## 8. Inspecting and verifying certificates

```bash
# Inspect any PEM certificate (human-readable)
step certificate inspect root_ca.crt
step certificate inspect intermediate_ca.crt
step certificate inspect device.crt

# Verify Intermediate CA chains to Root CA
step certificate verify intermediate_ca.crt --roots root_ca.crt

# Verify full device cert chain
step certificate verify device.crt --roots root_ca.crt

# Check CA health endpoint (Provider-Stack, from host)
curl -k https://localhost:9000/health
# Expected: {"status":"ok"}

# Check via step CLI (validates TLS against the Root CA)
step ca health --ca-url https://localhost:9000 --root root_ca.crt
```

### Inspect certificate from inside the container

```bash
docker compose exec step-ca step certificate inspect /home/step/certs/root_ca.crt
docker compose exec step-ca step certificate inspect /home/step/certs/intermediate_ca.crt
```

---

## 9. Issue a test certificate manually

Useful for verifying provisioner setup end-to-end.

```bash
cd provider-stack
source .env

# Bootstrap trust on the host
step ca bootstrap \
  --ca-url https://localhost:9000 \
  --fingerprint "${STEP_CA_FINGERPRINT}"

# Issue a test service cert (requires provisioner password)
step ca certificate test.service.local test.crt test.key \
  --ca-url https://localhost:9000 \
  --root ~/.step/certs/root_ca.crt \
  --provisioner iot-bridge \
  --provisioner-password-file <(echo "${STEP_CA_PROVISIONER_PASSWORD:-changeme}")

# Inspect the resulting cert
step certificate inspect test.crt

# Clean up
rm test.crt test.key
```

---

## 10. Troubleshooting

### `step-ca` fails to start — "certificate already exists"

**Cause:** The `step-ca-data` volume already contains a CA from a previous run with a
different `STEP_CA_PASSWORD`.

**Fix (destructive — deletes all issued certificates):**

```bash
cd provider-stack
docker compose down
docker volume rm provider-stack_step-ca-data
docker compose up -d step-ca
# After healthy: re-run init-provisioners.sh and update STEP_CA_FINGERPRINT
```

> After destroying the Root CA volume, all previously issued Tenant Sub-CA certs and
> device certs become invalid.  Re-run the JOIN workflow for every Tenant-Stack and
> re-enroll all devices.

### step-ca health check fails — "certificate signed by unknown authority"

**Cause:** The host `step` CLI is bootstrapped against a stale or different Root CA.

**Fix:**

```bash
# Re-bootstrap with the current fingerprint
cd provider-stack
FP=$(docker compose exec step-ca step certificate fingerprint /home/step/certs/root_ca.crt)
step ca bootstrap --ca-url https://localhost:9000 --fingerprint "$FP" --force
```

### `init-provisioners.sh` fails — "provisioner already exists"

The script is idempotent for most operations but may error if a provisioner with the
same name already exists.  Check current provisioners:

```bash
docker compose exec step-ca step ca provisioner list \
  --admin-subject step \
  --admin-provisioner "${STEP_CA_ADMIN_PROVISIONER:-cdm-admin@cdm.local}" \
  --admin-password-file /run/secrets/step-ca-password
```

If the provisioner already exists with correct settings, the error can be ignored.

### Tenant Sub-CA has wrong issuer after JOIN workflow

**Cause:** `init-sub-ca.sh` completed but the old self-signed boot cert was not replaced
correctly in the `step-ca-data` volume.

**Verify:**

```bash
cd tenant-stack
docker compose cp step-ca:/home/step/certs/intermediate_ca.crt ./tenant-sub-ca.crt
step certificate inspect tenant-sub-ca.crt | grep -E "Issuer|Subject|Not After"
# Issuer should contain the Provider Intermediate CA CN, NOT the tenant's own name
```

If the issuer is still the tenant's own name, the JOIN workflow did not complete correctly.
Re-run `init-sub-ca.sh`.
