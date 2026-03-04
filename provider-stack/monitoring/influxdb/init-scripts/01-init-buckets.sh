#!/bin/sh
# InfluxDB 2.x initialisation script
# Placed in /docker-entrypoint-initdb.d/ and executed once on first boot
# after the bucket/org created by DOCKER_INFLUXDB_INIT_* vars.
#
# Creates additional buckets and a read-only token used by Grafana.

set -eu

INFLUX="influx --host http://localhost:8086 --token ${DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}"

echo ">>> Creating device-events bucket (30-day retention)..."
$INFLUX bucket create \
  --name device-events \
  --org "${DOCKER_INFLUXDB_INIT_ORG}" \
  --retention 720h \
  || echo "Bucket device-events already exists, skipping."

echo ">>> Creating grafana read-only API token..."
$INFLUX auth create \
  --org "${DOCKER_INFLUXDB_INIT_ORG}" \
  --description "Grafana datasource (read-only)" \
  --read-bucket "$(
    $INFLUX bucket find --name iot-metrics --org "${DOCKER_INFLUXDB_INIT_ORG}" --hide-headers | awk '{print $1}'
  )" \
  --read-bucket "$(
    $INFLUX bucket find --name device-events --org "${DOCKER_INFLUXDB_INIT_ORG}" --hide-headers | awk '{print $1}'
  )" \
  || echo "Grafana token may already exist, skipping."

echo ">>> InfluxDB init complete."
