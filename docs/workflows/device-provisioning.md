# Device Provisioning Workflow

This page is the complete operational runbook for the zero-touch device provisioning flow.

---

## Overview

Zero-touch provisioning means a device can be unboxed, powered on, and fully registered in the platform without any manual intervention. The process relies on:

- A pre-installed `enroll.sh` script (or `rauc-hawkbit-updater` equivalent) baked into the Yocto image.
- The device knowing only: the `iot-bridge-api` URL and the step-ca root CA fingerprint.
- No pre-shared passwords — only asymmetric cryptography.

---

## Step-by-Step Flow

### Phase 1 — Factory Enrollment (first boot)

```
[Device]                     [IoT Bridge API]             [step-ca]
   │                                │                          │
   │── generate EC key pair         │                          │
   │── generate CSR (CN=device-id)  │                          │
   │                                │                          │
   │── POST /devices/{id}/enroll ──►│                          │
   │         { csr_pem: "..." }     │                          │
   │                                │── validate device-id     │
   │                                │── build OTT JWT          │
   │                                │── POST /1.0/sign ───────►│
   │                                │◄── signed cert ──────────│
   │                                │── allocate WG IP         │
   │                                │── generate WG config     │
   │◄── { cert, ca_chain, wg } ─────│                          │
   │                                │                          │
   │── save /certs/device.crt       │                          │
   │── save /certs/ca-chain.crt     │                          │
   │── save /certs/wg0.conf         │                          │
   │── write /certs/enrolled        │  (idempotency flag)      │
```

### Phase 2 — First MQTT Connection

```
[Device]                     [ThingsBoard]              [IoT Bridge API]
   │                                │                          │
   │── MQTT CONNECT (mTLS) ────────►│                          │
   │   (cert CN=device-id)          │── verify cert chain      │
   │                                │   against step-ca Root CA│
   │                                │                          │
   │                                │── Rule Engine fires      │
   │                                │   POST_CONNECT event     │
   │                                │── POST /webhooks/thingsboard ─►│
   │                                │                          │── create hawkBit target
   │                                │                          │── store WG IP in TB attributes
   │◄── CONNACK ────────────────────│                          │
```

### Phase 3 — Device Registers with WireGuard

```
[Device]                     [WireGuard Server]
   │                                │
   │── wg-quick up wg0 ────────────►│
   │   (uses /certs/wg0.conf)       │── add peer (public key + allowed IPs)
   │◄── tunnel established ─────────│
   │── now reachable at 10.8.0.x    │
```

---

## Configuration Reference

### iot-bridge-api Environment Variables

| Variable | Description | Example |
|---|---|---|
| `STEP_CA_URL` | step-ca API endpoint | `https://step-ca:9000` |
| `STEP_CA_FINGERPRINT` | Root CA SHA-256 fingerprint | `abc123...` |
| `STEP_CA_PROVISIONER_NAME` | JWK provisioner name | `iot-bridge` |
| `STEP_CA_PROVISIONER_PASSWORD` | JWK provisioner decrypt password | `...` |
| `HAWKBIT_URL` | hawkBit server URL | `http://hawkbit:8090` |
| `WG_SUBNET` | WireGuard allocation subnet | `10.8.0.0/24` |
| `WG_SERVER_ENDPOINT` | Public WireGuard endpoint | `vpn.example.com:51820` |
| `WG_SERVER_PUBLIC_KEY` | WireGuard server public key | `...` |

---

## Re-Enrollment

If a device loses its certificate (e.g. storage failure), delete the idempotency flag and re-run enrollment:

```bash
rm /certs/enrolled
/opt/cdm/enroll.sh
```

The `device_id` is preserved; a new key pair and certificate are generated.

---

## Decommissioning a Device

1. Revoke the device certificate in step-ca.
2. Delete the device from ThingsBoard.
3. Remove the device target from hawkBit.
4. Remove the WireGuard peer from the server config:
   ```bash
   wg set wg0 peer <device-public-key> remove
   wg-quick save wg0
   ```
5. Delete the device entry from `cdm_peers.json` (in the `wg-data` volume).

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| 422 on POST /enroll | Invalid CSR PEM | Re-generate CSR with correct CN |
| 503 on POST /enroll | step-ca unreachable | Check `STEP_CA_URL`, CA container health |
| MQTT CONNREFUSED | ThingsBoard not accepting mTLS | Check device profile, CA chain loaded |
| WireGuard not connecting | Server public key mismatch | Verify `WG_SERVER_PUBLIC_KEY` in `.env` |
