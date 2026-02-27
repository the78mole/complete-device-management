# Enroll Your First Device

This page explains every step of the device enrollment flow in detail.

!!! warning "Tenant-Stack required"
    Device enrollment runs against the **Tenant-Stack** (IoT Bridge API + step-ca Sub-CA).
    Make sure [Tenant-Stack Setup](../installation/tenant-stack.md) is complete before following this guide.

---

## Overview

Device enrollment is a one-time process that:

1. Generates a private key **on the device** — the key never leaves the device.
2. Creates a Certificate Signing Request (CSR) and sends it to the Tenant IoT Bridge API.
3. The API asks the Tenant **step-ca Sub-CA** to sign the certificate (chain: Device → Sub-CA → Root CA).
4. The signed certificate and CA chain are returned to the device.
5. The API also generates a WireGuard key pair and peer config for the device.
6. ThingsBoard is notified via its Rule Engine webhook when the device first connects.
7. The IoT Bridge API creates a corresponding target in hawkBit.

---

## Manual Enrollment (step-cli)

You can perform enrollment manually to understand each step.

### 1. Generate a Private Key and CSR

```bash
# Install step-cli: https://smallstep.com/docs/step-cli/installation
step crypto key pair device.key device.pub --kty EC --curve P-256 --no-password --insecure
step certificate create device-001 device.csr device.key \
  --csr --san device-001 --no-password --insecure
```

### 2. Send the CSR to the Tenant IoT Bridge API

Replace `TENANT_API` with the Tenant-Stack IoT Bridge API URL:

```bash
TENANT_API=https://tenant.example.com/api
CSR_PEM=$(cat device.csr)
curl -s -X POST "$TENANT_API/devices/device-001/enroll" \
  -H "Content-Type: application/json" \
  -d "{\"csr_pem\": \"$CSR_PEM\"}" | tee enroll_response.json | python3 -m json.tool
```

Expected response:

```json
{
  "device_id": "device-001",
  "certificate_pem": "-----BEGIN CERTIFICATE-----<br>...",
  "ca_chain_pem": "-----BEGIN CERTIFICATE-----<br>...",
  "wireguard_config": "[Interface]<br>PrivateKey = ...<br>..."
}
```

### 3. Save the Outputs

```bash
python3 -c "import json,sys; d=json.load(open('enroll_response.json')); \
  open('device.crt','w').write(d['certificate_pem']); \
  open('ca-chain.crt','w').write(d['ca_chain_pem']); \
  open('wg0.conf','w').write(d['wireguard_config'])"
```

### 4. Verify the Certificate

```bash
openssl x509 -in device.crt -noout -text | grep -A4 "Subject\|Issuer\|Validity\|Extended Key"
```

The issuer chain should read: `device-001` → Tenant Sub-CA → Provider ICA → Provider Root CA.

### 5. Connect via MQTT (mTLS)

```bash
mosquitto_pub \
  --host tenant.example.com --port 8883 \
  --cafile ca-chain.crt \
  --cert device.crt \
  --key device.key \
  --tls-version tlsv1.2 \
  -t "v1/devices/me/telemetry" \
  -m '{"test": 1}'
```

If the connection succeeds, the device appears in ThingsBoard (Tenant-Stack) immediately.

---

## Automated Enrollment (docker compose)

The `device-stack/bootstrap` container automates all of the above via `enroll.sh`. It is
idempotent — if `/certs/enrolled` exists, it skips re-enrollment.

```bash
cd device-stack
docker compose up bootstrap   # runs once and exits with code 0
```

---

## Certificate Renewal

Certificates issued by the Tenant step-ca have a configurable validity. To renew:

```bash
step ca renew --force device.crt device.key \
  --ca-url https://tenant.example.com/pki \
  --root ca-chain.crt
```

In production, configure the `step-ca` renewal daemon or a systemd timer.

---

## Revoking a Certificate

If a device is decommissioned or compromised:

```bash
step ca revoke --cert device.crt --key device.key \
  --ca-url https://tenant.example.com/pki --root ca-chain.crt
```

Then delete the device in ThingsBoard and hawkBit.
For escalated revocation (compromise of the Sub-CA), see
[Security Incident Response](../use-cases/security-incident-response.md).

