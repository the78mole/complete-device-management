# OTA Update Workflow

This page covers the full OTA software lifecycle — from uploading a bundle to monitoring rollout success across the fleet.

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

## Full Rollout Procedure

### 1. Build and Sign the Bundle

On your build system (CI/CD):

```bash
# Sign the RAUC bundle with the signing certificate
rauc bundle \
  --cert rauc-signing.crt \
  --key rauc-signing.key \
  rootfs-1.1.0.tar.gz \
  cdm-os-1.1.0.raucb
```

### 2. Create a Software Module in hawkBit

```bash
# Via hawkBit REST API
curl -X POST http://localhost:8090/rest/v1/softwaremodules \
  -u admin:admin -H "Content-Type: application/json" \
  -d '{"name":"cdm-os","version":"1.1.0","type":"os"}'
```

Upload the bundle:

```bash
curl -X POST "http://localhost:8090/rest/v1/softwaremodules/{id}/artifacts" \
  -u admin:admin -F "file=@cdm-os-1.1.0.raucb"
```

### 3. Create a Distribution Set

```bash
curl -X POST http://localhost:8090/rest/v1/distributionsets \
  -u admin:admin -H "Content-Type: application/json" \
  -d '{"name":"cdm-release-1.1.0","version":"1.1.0","modules":[{"id":<module_id>}]}'
```

### 4. Create a Rollout with Staged Groups

For a staged rollout (canary → 10% → 50% → 100%):

```bash
curl -X POST http://localhost:8090/rest/v1/rollouts \
  -u admin:admin -H "Content-Type: application/json" \
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
