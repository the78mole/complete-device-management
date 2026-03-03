#!/bin/sh
# TimescaleDB initialisation – CDM Provider Stack
#
# Placed in /docker-entrypoint-initdb.d/ and executed once on first boot.
# Creates the TimescaleDB extension, write user (telegraf) and read user (grafana).
#
# Environment variables (injected by docker-compose):
#   TSDB_TELEGRAF_PASSWORD  – password for the telegraf write user
#   TSDB_GRAFANA_PASSWORD   – password for the grafana read-only user

set -eu

PSQL="psql -v ON_ERROR_STOP=1 --username postgres --dbname ${POSTGRES_DB:-cdm}"

echo ">>> Enabling TimescaleDB extension..."
$PSQL -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

echo ">>> Creating telegraf write user..."
$PSQL -c "CREATE USER telegraf WITH PASSWORD '${TSDB_TELEGRAF_PASSWORD:-changeme}';"
$PSQL -c "GRANT CONNECT ON DATABASE ${POSTGRES_DB:-cdm} TO telegraf;"
$PSQL -c "GRANT USAGE ON SCHEMA public TO telegraf;"
$PSQL -c "GRANT CREATE ON SCHEMA public TO telegraf;"
$PSQL -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT INSERT, SELECT ON TABLES TO telegraf;"

echo ">>> Creating grafana read-only user..."
$PSQL -c "CREATE USER grafana WITH PASSWORD '${TSDB_GRAFANA_PASSWORD:-changeme}';"
$PSQL -c "GRANT CONNECT ON DATABASE ${POSTGRES_DB:-cdm} TO grafana;"
$PSQL -c "GRANT USAGE ON SCHEMA public TO grafana;"
# Grant SELECT for tables created by postgres itself
$PSQL -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana;"
# Grant SELECT for tables created by the telegraf write user (all metric tables)
$PSQL -c "ALTER DEFAULT PRIVILEGES FOR ROLE telegraf IN SCHEMA public GRANT SELECT ON TABLES TO grafana;"

echo ">>> TimescaleDB init complete."
