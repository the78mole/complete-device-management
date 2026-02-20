# Fleet Management

This use case describes how to manage a large fleet of IoT devices across multiple tenants using **Complete Device Management**.

---

## Scenario

An industrial equipment manufacturer ships 500 Linux-based controllers to customers across three regions. Each customer is a separate tenant. The manufacturer needs to:

- Provision all devices automatically when they first power on at the customer site.
- Push firmware updates in a controlled, staged manner without disrupting production.
- Monitor device health in real time.
- Allow on-call engineers to remotely debug devices without VPN client software on their laptops.

---

## Setup

### 1. Create Tenants

For each customer, create an organisation in Keycloak:

1. Log in to Keycloak → `cdm` realm → **Groups → New Group** → `customer-a`.
2. The `tenant-sync-service` automatically creates:
   - A ThingsBoard tenant: `Customer A`
   - A Grafana organisation: `Customer A`

### 2. Assign Operators

Add operator users to the customer group in Keycloak. They receive:

- `cdm-operator` role → ThingsBoard Customer User, hawkBit read + trigger, Grafana Editor.

### 3. Pre-configure Device Images

Bake the following into the Yocto OS image before shipping:

```
/opt/cdm/enroll.sh        — enrollment script
/opt/cdm/ca-fingerprint   — step-ca root CA fingerprint
/etc/cdm/device-config    — BRIDGE_API_URL, TB_MQTT_HOST, HAWKBIT_URL, INFLUXDB_URL
```

The device ID is derived from the hardware serial number at first boot.

---

## Day-to-Day Operations

### Viewing the Fleet

1. Open ThingsBoard → **Devices** (filter by tenant or device profile `cdm-x509`).
2. The device list shows:
   - Online/offline status (last activity timestamp)
   - Current firmware version (`sw_version` attribute)
   - WireGuard IP
   - Active alarm count

### Triggering a Fleet-Wide Firmware Update

1. Build and sign the RAUC bundle in CI/CD.
2. Upload to hawkBit (automate via REST API in your CI pipeline).
3. Create a rollout:
   - Group 1: 5% of devices (canary) — `actionType: soft` (device installs at next reboot)
   - Group 2: 25% — activated after Group 1 reaches 95% success
   - Group 3: 70% — activated after Group 2 reaches 95% success
4. Monitor in hawkBit Rollout view and Grafana OTA dashboard.

### Handling a Failed Update

If a device reports `ota_status: failure`:

1. ThingsBoard raises an **OTA Failure** alarm.
2. Operator opens the Terminal Widget and inspects logs:
   ```bash
   journalctl -u rauc-hawkbit-updater -n 50
   rauc status
   ```
3. If the bundle was corrupt, re-upload a corrected version and re-trigger the deployment.
4. RAUC automatically reverts to the previous slot after failed boot attempts.

---

## Scaling Considerations

| Scale | Recommendation |
|---|---|
| < 100 devices | Single Docker Compose node is sufficient |
| 100–1000 devices | Separate DB nodes (managed PostgreSQL, MySQL); keep app containers on Docker Compose |
| > 1000 devices | Move to Kubernetes with Helm charts; scale ThingsBoard and InfluxDB horizontally |
| > 10,000 devices | Consider ThingsBoard PE (cluster mode), InfluxDB Clustered, and hawkBit cluster |
