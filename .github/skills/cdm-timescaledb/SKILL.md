````skill
# CDM Skill — TimescaleDB, pgAdmin & Telegraf (Provider Monitoring)

This document covers the provider-side observability stack:
**TimescaleDB** (PostgreSQL 17 + TimescaleDB extension) as the metrics store,
**pgAdmin** for database access via OIDC SSO, **Telegraf** as the metrics collector, and
**Grafana** for dashboards — all running in the **provider-stack**.

---

## 1. Architecture overview

```
Provider service health+MQTT telemetry
  │
  ▼
Telegraf (provider-telegraf)
  │  http_response inputs → polls Keycloak / Grafana / IoT Bridge / RabbitMQ / step-ca
  │  rabbitmq input → queue depths, message rates
  │  mqtt_consumer (mTLS tls://rabbitmq:8883, topic cdm/provider/#)
  │  Writes all measurements via postgresql output
  ▼
TimescaleDB (provider-timescaledb :5432)
  │  Database: cdm   Users: telegraf (write), grafana (read), postgres (superuser)
  │  pgAdmin connects as postgres via pg_service.conf (no password dialog)
  ▼
Grafana (provider-grafana)             pgAdmin (provider-pgadmin)
  │  PostgreSQL datasource             │  pg_service.conf → libpq auth
  │  (grafana-postgresql-datasource)   │  OIDC login via Keycloak cdm realm
  ▼                                    ▼
  system-monitor dashboard             Query Tool / ERD / data browser
```

---

## 2. Services (provider-stack)

| Service | Container | Port | Notes |
|---|---|---|---|
| TimescaleDB | `provider-timescaledb` | 5432 (internal) | `timescale/timescaledb-ha:pg17` |
| pgAdmin | `provider-pgadmin` | 80 (Caddy → `/pgadmin/`) | Custom entrypoint + `oidc-proxy.py` |
| Telegraf | `provider-telegraf` | — (no ingress) | Writes only, no inbound port |
| Grafana | `provider-grafana` | 3000 (Caddy → `/grafana/`) | Pre-provisioned with system-monitor dashboard |

---

## 3. TimescaleDB schema

Initialised by `provider-stack/monitoring/timescaledb/init-scripts/01-init-schema.sh`
on first boot.  Telegraf auto-creates hypertables on first write.

| Table (hypertable) | Created by | Content | Typical retention |
|---|---|---|---|
| `http_response` | Telegraf auto-create | HTTP health checks for all provider services | 30 days |
| `rabbitmq` | Telegraf auto-create | RabbitMQ queue depths, message rates, connections | 30 days |
| `provider_system` | Telegraf auto-create (MQTT consumer) | System-monitor metrics from `cdm/provider/#` topic | 90 days |

### Database users

| User | Role | Password env var |
|---|---|---|
| `postgres` | Superuser | `TSDB_PASSWORD` |
| `telegraf` | Write (CREATE + INSERT + SELECT on public schema) | `TSDB_TELEGRAF_PASSWORD` |
| `grafana` | Read-only (SELECT on all telegraf-created tables) | `TSDB_GRAFANA_PASSWORD` |

The `ALTER DEFAULT PRIVILEGES FOR ROLE telegraf IN SCHEMA public GRANT SELECT ON TABLES TO grafana`
grant ensures Grafana can read every table Telegraf creates, without needing manual GRANT statements.

---

## 4. pgAdmin — OIDC auth & password-less database access

### OIDC login

pgAdmin uses `oidc-proxy.py` (a lightweight Flask proxy) and is configured
for **OIDC authentication** against the `pgadmin` client in Keycloak's `cdm` realm.
The client secret is stored in `PGADMIN_OIDC_SECRET`.

### Password-less database connection (pg_service.conf)

pgAdmin passes database credentials to **libpq** via a service file, bypassing pgAdmin's
own password storage entirely.  This prevents the "please enter password" dialog for OIDC users.

`docker-entrypoint.sh` creates `/var/lib/pgadmin/pg_service.conf` at startup:

```ini
[cdm_admin]
host=timescaledb
port=5432
dbname=cdm
user=postgres
password=<TSDB_PASSWORD at runtime>
```

The file is referenced via the `PGSERVICEFILE=/var/lib/pgadmin/pg_service.conf` environment
variable (set in `docker-compose.yml`), which libpq reads automatically.

A background loop in `docker-entrypoint.sh` ensures the SQLite rows in both the `server` and
`sharedserver` tables always carry `service='cdm_admin'`, `save_password=0`, `password=NULL`.

### servers.json `"Service"` key

`provider-stack/pgadmin/servers.json` declares the pre-provisioned connection:

```json
{
  "Servers": {
    "1": {
      "Name": "CDM TimescaleDB",
      "Service": "cdm_admin",
      ...
    }
  }
}
```

`"Service": "cdm_admin"` resolves to the `[cdm_admin]` entry in `pg_service.conf`.
Do **not** add `"PassFile"` or `"PassExecCmd"` — the service lookup is sufficient and
`passexec_cmd` does not exist in the `sharedserver` SQLite table, which would cause a crash.

---

## 5. Telegraf configuration

Config: `provider-stack/monitoring/telegraf/telegraf.conf`

### Global tags

```toml
[global_tags]
  component = "provider"
```

All metrics are tagged with `component = "provider"` — there is no `device_id` tag.

### Inputs

| Plugin | Metrics | Interval |
|---|---|---|
| `http_response` (×4 stanzas) | HTTP 2xx / response_time for Keycloak, Grafana, IoT Bridge API, RabbitMQ, step-ca | 60s |
| `rabbitmq` | Queue depths, message rates, connection counts (Basic Auth) | 60s |
| `mqtt_consumer` (mTLS) | System monitor messages on `cdm/provider/#` from RabbitMQ | on message |

The `mqtt_consumer` connects to RabbitMQ with mTLS (`tls://rabbitmq:8883`).
The client certificate (CN=`telegraf`) is issued by Provider step-ca at stack start
by the `mqtt-certs-init` service.  No password — RabbitMQ maps CN → user via EXTERNAL SASL.

### Output — Provider TimescaleDB

```toml
[[outputs.postgresql]]
  connection = "postgresql://telegraf:$TSDB_TELEGRAF_PASSWORD@$TSDB_HOST:$TSDB_PORT/$TSDB_DATABASE?sslmode=disable"
  schema = "public"
  tags_as_foreign_keys = false
```

Telegraf automatically creates one hypertable per measurement.

---

## 6. Grafana datasource

Grafana uses the **`grafana-postgresql-datasource`** plugin (not the legacy `postgres` type).
Pre-provisioned datasource in `provider-stack/monitoring/grafana/datasources/`:

```yaml
datasources:
  - name: TimescaleDB
    type: grafana-postgresql-datasource
    url: timescaledb:5432
    database: cdm
    jsonData:
      timescaledb: true
      sslmode: disable
```

### system-monitor dashboard

Pre-loaded from `provider-stack/monitoring/grafana/dashboards/system-monitor.json`.
Queries the `provider_system` hypertable for:

- CPU load averages (1m / 5m / 15m) — timeseries + gauge
- RAM used % — timeseries + gauge + stat

---

## 7. Key environment variables

All in `provider-stack/.env` / `.env.example`:

| Variable | Used by | Notes |
|---|---|---|
| `TSDB_PASSWORD` | TimescaleDB container, pgAdmin pg_service.conf | PostgreSQL superuser |
| `TSDB_TELEGRAF_PASSWORD` | Telegraf output | Write user |
| `TSDB_GRAFANA_PASSWORD` | Grafana datasource | Read-only user |
| `PGADMIN_EMAIL` | pgAdmin | Default login (also used as superuser email) |
| `PGADMIN_PASSWORD` | pgAdmin | Password for `PGADMIN_EMAIL` (master password for initial setup) |
| `PGADMIN_OIDC_SECRET` | pgAdmin `oidc-proxy.py` | Keycloak `pgadmin` client secret in `cdm` realm |

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| pgAdmin: "please enter password" dialog | SQLite `service` column not yet set | Wait for `docker-entrypoint.sh` background loop (runs every 60 s); check pgadmin container logs |
| pgAdmin: `'NoneType' object has no attribute 'connection'` | `passexec_cmd` column in `server`/`sharedserver` table | Ensure `docker-entrypoint.sh` only sets `service`, `save_password`, `password` — never `passexec_cmd` |
| No metrics in Grafana | Telegraf not writing | `docker logs provider-telegraf`; check `TSDB_TELEGRAF_PASSWORD` and TimescaleDB connectivity |
| Grafana datasource error | Wrong plugin type | Verify datasource type is `grafana-postgresql-datasource`, not `postgres` |
| Telegraf `password authentication failed` | Wrong `TSDB_TELEGRAF_PASSWORD` | Update `.env` and `docker compose restart telegraf` |
| Telegraf MQTT cert error | `mqtt-certs-init` did not run | `docker compose restart mqtt-certs-init telegraf` |
````
