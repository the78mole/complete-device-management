#!/bin/sh
# InfluxDB 2.x initialisation script – Tenant Stack
# Placed in /docker-entrypoint-initdb.d/ and executed once on first boot
# after the bucket/org created by DOCKER_INFLUXDB_INIT_* vars.
#
# Creates additional buckets:
#   device-telemetry  – main MQTT telemetry (30-day retention, created by init vars)
#   device-events     – state changes, firmware updates, alerts (30-day)
#   device-audit      – security / enrollment events (90-day)
#
# Also creates a read-only Grafana token.

set -eu

INFLUX="influx --host http://localhost:8086 --token ${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}"
ORG="${DOCKER_INFLUXDB_INIT_ORG}"

echo ">>> Creating device-events bucket (30-day retention)..."
$INFLUX bucket create \
  --name device-events \
  --org "$ORG" \
  --retention 720h \
  || echo "Bucket device-events already exists, skipping."

echo ">>> Creating device-audit bucket (90-day retention)..."
$INFLUX bucket create \
  --name device-audit \
  --org "$ORG" \
  --retention 2160h \
  || echo "Bucket device-audit already exists, skipping."

echo ">>> Creating Grafana read-only API token..."
$INFLUX auth create \
  --org "$ORG" \
  --description "Grafana datasource (read-only)" \
  --read-bucket "$($INFLUX bucket find --name device-telemetry --org "$ORG" --hide-headers | awk '{print $1}')" \
  --read-bucket "$($INFLUX bucket find --name device-events    --org "$ORG" --hide-headers | awk '{print $1}')" \
  --read-bucket "$($INFLUX bucket find --name device-audit     --org "$ORG" --hide-headers | awk '{print $1}')" \
  || echo "Grafana token may already exist, skipping."

echo ">>> InfluxDB init complete."
