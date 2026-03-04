#!/bin/sh
# publish-telemetry.sh
#
# Publishes simulated device telemetry to Tenant ThingsBoard via MQTT TLS (mTLS).
# Uses the X.509 certificate written by the bootstrap container during enrollment
# against the Tenant IoT Bridge API (cert signed by Tenant Sub-CA).
#
# ThingsBoard X.509 device authentication: the device sends its certificate
# as the MQTT username; the password field is unused for certificate auth.
# Topic: v1/devices/me/telemetry
# Broker: Tenant ThingsBoard MQTT on port 8883 (direct, not via Caddy)

set -eu

THINGSBOARD_HOST="${THINGSBOARD_HOST:-host.docker.internal}"
THINGSBOARD_MQTT_PORT="${THINGSBOARD_MQTT_PORT:-8883}"
DEVICE_ID="${DEVICE_ID:-sim-device-001}"
INTERVAL="${TELEMETRY_INTERVAL_S:-30}"

CERT="/certs/device.pem"
KEY="/certs/device-key.pem"
CA="/certs/ca-chain.pem"
ENROLLED="/certs/.enrolled"

# ── Wait for enrollment to complete ──────────────────────────────────────────
echo "[mqtt] Waiting for device enrollment…"
while [ ! -f "$ENROLLED" ]; do sleep 2; done
echo "[mqtt] Device enrolled – starting telemetry loop."

# ── Seed for pseudo-random values ────────────────────────────────────────────
# Alpine sh does not have $RANDOM, so use /dev/urandom for variability
rand_int() {
    min=$1
    max=$2
    range=$((max - min + 1))
    val=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
    echo $(( (val % range) + min ))
}

# ── Publish loop ─────────────────────────────────────────────────────────────
SEQ=0
while true; do
    SEQ=$((SEQ + 1))
    CPU=$(rand_int 5 85)
    RAM=$(rand_int 30 90)
    DISK=$(rand_int 10 70)
    TEMP=$(rand_int 38 72)
    RSSI=$(rand_int -95 -40)
    OTA_STATUS="idle"

    PAYLOAD=$(printf \
        '{"sequence":%d,"cpu_percent":%d,"ram_percent":%d,"disk_percent":%d,"temperature_c":%d,"rssi_dbm":%d,"ota_status":"%s","device_id":"%s"}' \
        "$SEQ" "$CPU" "$RAM" "$DISK" "$TEMP" "$RSSI" "$OTA_STATUS" "$DEVICE_ID")

    echo "[mqtt] Sending telemetry #${SEQ}: ${PAYLOAD}"

    mosquitto_pub \
        --host    "$THINGSBOARD_HOST" \
        --port    "$THINGSBOARD_MQTT_PORT" \
        --topic   "v1/devices/me/telemetry" \
        --message "$PAYLOAD" \
        --cert    "$CERT" \
        --key     "$KEY" \
        --cafile  "$CA" \
        --tls-version tlsv1.2 \
        --id      "$DEVICE_ID" \
        --qos 1 \
        2>&1 || echo "[mqtt] WARNING: publish failed – will retry in ${INTERVAL}s"

    sleep "$INTERVAL"
done
