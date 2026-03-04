#!/bin/sh
# TimescaleDB initialisation – CDM Tenant Stack (unified DB)
#
# Placed in /docker-entrypoint-initdb.d/ and executed once on first boot.
# Runs as the PostgreSQL superuser (postgres).
#
# Creates:
#   1. ThingsBoard application user + grants ownership of the default DB
#   2. Tenant analytics database (TENANT_ID) with TimescaleDB extension
#   3. telegraf write user + grafana read-only user for the analytics DB
#
# Environment variables (injected by docker-compose):
#   POSTGRES_DB             – ThingsBoard database name (= "thingsboard")
#   TB_DB_PASSWORD          – password for the thingsboard app user
#   TENANT_ID               – tenant analytics database name
#   TSDB_TELEGRAF_PASSWORD  – password for the telegraf write user
#   TSDB_GRAFANA_PASSWORD   – password for the grafana read-only user

set -eu

TB_DB="${POSTGRES_DB:-thingsboard}"
ANALYTICS_DB="${TENANT_ID:-tenant}"

# ── 1. ThingsBoard application user ──────────────────────────────────────
echo ">>> Creating ThingsBoard application user..."
psql -v ON_ERROR_STOP=1 --username postgres --dbname "$TB_DB" <<-SQL
    CREATE USER thingsboard WITH PASSWORD '${TB_DB_PASSWORD:-changeme}';
    GRANT ALL PRIVILEGES ON DATABASE "$TB_DB" TO thingsboard;
    ALTER DATABASE "$TB_DB" OWNER TO thingsboard;
SQL

# ── 2. Analytics database (TimescaleDB) ─────────────────────────────
echo ">>> Creating analytics database \"$ANALYTICS_DB\"..."
psql -v ON_ERROR_STOP=1 --username postgres --dbname postgres \
    -c "CREATE DATABASE \"$ANALYTICS_DB\" OWNER postgres;"

echo ">>> Enabling TimescaleDB extension..."
psql -v ON_ERROR_STOP=1 --username postgres --dbname "$ANALYTICS_DB" \
    -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

# ── 3. Analytics users ───────────────────────────────────────────────
echo ">>> Creating telegraf write user..."
psql -v ON_ERROR_STOP=1 --username postgres --dbname "$ANALYTICS_DB" <<-SQL
    CREATE USER telegraf WITH PASSWORD '${TSDB_TELEGRAF_PASSWORD:-changeme}';
    GRANT CONNECT ON DATABASE "$ANALYTICS_DB" TO telegraf;
    GRANT USAGE ON SCHEMA public TO telegraf;
    GRANT CREATE ON SCHEMA public TO telegraf;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT INSERT, SELECT ON TABLES TO telegraf;
SQL

echo ">>> Creating grafana read-only user..."
psql -v ON_ERROR_STOP=1 --username postgres --dbname "$ANALYTICS_DB" <<-SQL
    CREATE USER grafana WITH PASSWORD '${TSDB_GRAFANA_PASSWORD:-changeme}';
    GRANT CONNECT ON DATABASE "$ANALYTICS_DB" TO grafana;
    GRANT USAGE ON SCHEMA public TO grafana;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana;
SQL

echo ">>> Unified DB init complete (thingsboard + analytics=$ANALYTICS_DB)."
