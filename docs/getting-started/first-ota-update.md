# Trigger Your First OTA Update

!!! warning "Phase 2 — Tenant-Stack required"
    hawkBit, ThingsBoard, and the OTA update pipeline are part of the
    **Tenant-Stack**, which is available in Phase 2.  The steps below will work
    once a Tenant-Stack is deployed and the device is enrolled.
    See [Tenant-Stack Setup](../installation/tenant-stack.md).

This guide shows you how to upload a software bundle to hawkBit and deploy it to a device.

---

## Prerequisites

- The Tenant-Stack is running (ThingsBoard + hawkBit bootstrapped).
- At least one device is enrolled and connected (see [Enroll Your First Device](first-device.md)).
- The device's `rauc-hawkbit-updater` service (or `ddi-poll.sh` simulation) is running.

---

## 1. Log In to hawkBit

Open **https://tenant.example.com/hawkbit** in your browser (replace with your Tenant-Stack hostname).

Default credentials:

- **Username:** `admin`
- **Password:** `admin`

---

## 2. Upload a Software Bundle

1. Go to **Upload** in the left navigation.
2. Create a new **Software Module**:
   - **Name:** `cdm-os-image`
   - **Version:** `1.0.0`
   - **Type:** `OS`
3. Upload a bundle file. For testing, you can use any file (the simulation does not check the content).
4. Create a **Distribution Set**:
   - **Name:** `cdm-release-1.0.0`
   - **Version:** `1.0.0`
   - Assign your software module to it.

---

## 3. Create a Rollout Campaign

1. Go to **Rollout** in the left navigation.
2. Click **Create Rollout**.
3. Fill in:
   - **Name:** `test-rollout-1`
   - **Distribution Set:** `cdm-release-1.0.0`
   - **Target Filter:** `name==device-001` (or `*` for all devices)
   - **Action Type:** `Forced`
   - **Groups:** 1 group, 100% of targets
4. Click **Create** and then **Start** the rollout.

---

## 4. Watch the Device Receive and Apply the Update

On the device side, the DDI poller (`ddi-poll.sh` or `rauc-hawkbit-updater`) checks hawkBit every 30 seconds. When it detects a pending deployment:

```
[ddi-poll] Polling hawkBit DDI...
[ddi-poll] Deployment action found: action-id=42
[ddi-poll] Downloading artefacts...
[ddi-poll] Simulating RAUC install (slot B)...
[ddi-poll] Reporting success to hawkBit...
[ddi-poll] Update complete.
```

!!! note "Real Hardware"
    On a real Yocto device with RAUC installed, `rauc-hawkbit-updater` downloads the bundle and calls `rauc install` on the inactive A/B partition. After a successful install, the device reboots into the new slot.

---

## 5. Verify the Update Status in hawkBit

1. Go to **Deployment** in hawkBit.
2. Find `device-001` — the status should show **Finished: Success**.

---

## 6. Verify the Update Status in ThingsBoard

The device reports its OTA status back via MQTT. In ThingsBoard:

1. Open the `device-001` device.
2. Check **Latest Telemetry** for the key `sw_version` — it should show `1.0.0`.
3. Check **Attributes** for `rauc_slot` — it should reflect the active boot slot.

---

## Next Steps

- [OTA Updates Workflow](../workflows/ota-updates.md) — full rollout strategies, staged rollouts, and rollback.
- [Monitoring](../workflows/monitoring.md) — track update success rates across the fleet in Grafana.
