# Monitoring & Telemetry Workflow

This page covers how device metrics flow from the edge to TimescaleDB (PostgreSQL 17 +
TimescaleDB extension) and how to use the Grafana dashboards.

---

## Architecture

```mermaid
graph LR
    subgraph edge[Edge Device]
        TEL[Telegraf]
        MQC[MQTT client]
    end

    subgraph tenant[Tenant-Stack]
        TB[ThingsBoard]
        TSDB_T[TimescaleDB]
        GRF_T[Grafana]
        TSDB_T --> GRF_T
    end

    subgraph provider[Provider-Stack]
        RMQ[RabbitMQ]
        TSDB_P[TimescaleDB]
        GRF_P["Grafana (platform)"]
        TSDB_P --> GRF_P
    end

    TEL -->|"PostgreSQL wire protocol"| TSDB_T
    MQC -->|MQTTS| TB
    TB -->|Rule Engine| ALM["Alarms / Notifications"]
    TB -->|"AMQP (optional)"| RMQ
    RMQ -->|cdm-metrics vHost| TSDB_P
```

**Principle:** High-frequency, high-cardinality data (every 10 seconds per device) goes
directly to the Tenant TimescaleDB.  Business-logic data (device state, alarms, OTA status)
goes through ThingsBoard.  Optionally, the ThingsBoard Rule Engine forwards aggregated
platform-health metrics via RabbitMQ to the Provider TimescaleDB for fleet-wide visibility.

---

## Telegraf Configuration

The Telegraf config is at `device-stack/telegraf/telegraf.conf`. Key sections:

### Inputs

| Plugin | Metrics | Interval |
|---|---|---|
| `cpu` | usage_user, usage_system, usage_idle | 10s |
| `mem` | used_percent, available, free | 10s |
| `disk` | used_percent, free, total | 30s |
| `net` | bytes_sent, bytes_recv, drop_in, drop_out | 10s |
| `exec` | Custom metrics from user scripts | configurable |
| `mqtt_consumer` | Parses device MQTT messages as tags | on message |

### Output — Tenant TimescaleDB

```toml
[[outputs.postgresql]]
  connection = "postgresql://telegraf:${TSDB_TELEGRAF_PASSWORD}@timescaledb:5432/${TSDB_DATABASE}?sslmode=disable"
  schema = "public"
  tags_as_foreign_keys = false
  create_metrics_table_if_not_exists = true
  [outputs.postgresql.timescaledb]
    enabled = true
    disable_compression = false
    chunk_time_interval = "1d"
```

Telegraf automatically creates one hypertable per measurement (e.g. `cpu`, `mem`, `disk`).
The `time` column is the hypertable partition key.

### Adding Custom Metrics

To collect application-specific metrics, add an `exec` input:

```toml
[[inputs.exec]]
  commands = ["/opt/cdm/metrics/my-app-metrics.sh"]
  timeout = "5s"
  data_format = "json"
  interval = "30s"
  name_override = "my_app"
```

---

## TimescaleDB Tables

**Tenant TimescaleDB** (`${TENANT_ID}` database) — device-facing:

| Table (hypertable) | Retention | Content |
|---|---|---|
| `device_telemetry` | 30 days | All Telegraf metrics from devices |
| `device_events` | 90 days | Device state changes, OTA events |
| `device_audit` | 90 days | Enrollment, certificate events |
| `<measurement>` | configurable | Auto-created by Telegraf per measurement |

**Provider TimescaleDB** (`cdm` database) — platform-facing:

| Table (hypertable) | Retention | Content |
|---|---|---|
| `iot_metrics` | 90 days | Aggregated metrics from all tenants via RabbitMQ |
| `device_events` | 1 year | Enrollment events, revocations |
| `<measurement>` | configurable | Auto-created by Telegraf per measurement |

Tables and hypertables are created automatically by `monitoring/timescaledb/init-scripts/01-init-schema.sh`.
Telegraf creates additional tables on first write.

---

## Grafana Dashboards

Grafana is pre-provisioned with two dashboards:

### Device Overview

Shows for a selected device (variable `$device_id`):

- CPU usage (sparkline + gauge)
- Memory used %
- Disk used %
- Network throughput (bytes sent/recv)

### Fleet Summary

Shows across all devices:

- Online device count (last heartbeat < 5 min)
- P50 / P95 CPU usage across fleet
- OTA success rate (from `device_events` table)
- Devices with disk > 80%

In Grafana, the datasource type is **PostgreSQL** with TimescaleDB enabled:
- **Configuration → Data Sources → TimescaleDB** — ensure the datasource is working.
- Queries use standard SQL with TimescaleDB functions:
  ```sql
  SELECT
    time_bucket('1 minute', time) AS bucket,
    avg(usage_user) AS cpu_avg
  FROM cpu
  WHERE device_id = '${device_id}'
    AND time > NOW() - INTERVAL '1 hour'
  GROUP BY bucket
  ORDER BY bucket;
  ```

---

## Alerting

ThingsBoard handles device-level alerting:

- High CPU (> 90% for 5 min) → alarm in ThingsBoard → notification email/Slack
- Disk full (> 95%) → critical alarm
- Device offline (no telemetry for 10 min) → `Inactive` state in ThingsBoard

Grafana + TimescaleDB handles fleet-level alerting:

- OTA error rate > 5% → Grafana Alert → PagerDuty / email
- Average memory usage across fleet > 80% → warning alert

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No metrics in TimescaleDB | Telegraf can't reach TimescaleDB | Check `TSDB_DATABASE`, `TSDB_TELEGRAF_PASSWORD` in device `.env` |
| Grafana shows "No data" | Wrong table name or time range | Verify table name matches; widen time range |
| ThingsBoard telemetry stops | MQTT client disconnected | Check `mqtt-client` logs; verify cert validity |
| Missing device in Fleet dashboard | Telegraf tag `device_id` not set | Add `[global_tags] device_id = "${DEVICE_ID}"` to `telegraf.conf` |
| Telegraf: `password authentication failed` | Wrong `TSDB_TELEGRAF_PASSWORD` | Check `.env` and restart `docker compose restart telegraf` |
