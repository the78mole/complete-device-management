"""InfluxDB v2 client – replaced by TimescaleDB.

This module is kept for backward compatibility only.
All telemetry writes now go through :mod:`app.clients.timescaledb`.
"""
# Deprecated: use app.clients.timescaledb instead.
from app.clients.timescaledb import TimescaleDBClient as InfluxDBClient  # noqa: F401
from app.clients.timescaledb import TimescaleDBError as InfluxDBError  # noqa: F401

__all__ = ["InfluxDBClient", "InfluxDBError"]
