"""TimescaleDB (PostgreSQL 17) async write client.

Uses asyncpg for high-performance, fully async PostgreSQL connectivity.
The client writes device telemetry into the ``device_telemetry`` hypertable
that is created by the TimescaleDB init script on first container start.

Schema (created in monitoring/timescaledb/init-scripts/01-init-schema.sh):

    CREATE TABLE device_telemetry (
        time        TIMESTAMPTZ NOT NULL,
        tenant_id   TEXT        NOT NULL,
        device_id   TEXT        NOT NULL,
        metric_name TEXT        NOT NULL,
        value       DOUBLE PRECISION,
        tags        JSONB
    );

The ``telegraf`` PostgreSQL user has INSERT / CREATE on this schema.
The ``grafana`` user has SELECT only.
"""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime
from typing import Any

import asyncpg

logger = logging.getLogger(__name__)

_INSERT_SQL = """
INSERT INTO device_telemetry (time, tenant_id, device_id, metric_name, value, tags)
VALUES ($1, $2, $3, $4, $5, $6)
"""


class TimescaleDBError(Exception):
    """Raised when a TimescaleDB write operation fails."""


class TimescaleDBClient:
    """Async client for writing device telemetry to TimescaleDB."""

    def __init__(
        self,
        host: str,
        port: int,
        database: str,
        user: str = "telegraf",
        password: str = "",
    ) -> None:
        self._dsn = (
            f"postgresql://{user}:{password}@{host}:{port}/{database}"
        )
        self._pool: asyncpg.Pool | None = None

    async def _get_pool(self) -> asyncpg.Pool:
        if self._pool is None:
            try:
                self._pool = await asyncpg.create_pool(
                    self._dsn,
                    min_size=1,
                    max_size=5,
                    command_timeout=10,
                )
            except Exception as exc:
                raise TimescaleDBError(
                    f"Failed to connect to TimescaleDB: {exc}"
                ) from exc
        return self._pool

    async def write_metrics(
        self,
        rows: list[dict[str, Any]],
    ) -> None:
        """Insert a batch of metric rows into ``device_telemetry``.

        Each row dict must contain:
            tenant_id   (str)
            device_id   (str)
            metric_name (str)
            value       (float | None)
            tags        (dict | None)  – stored as JSONB

        Args:
            rows: Non-empty list of metric row dicts.

        Raises:
            TimescaleDBError: on any database error.
        """
        if not rows:
            return
        if not self._dsn:
            logger.warning(
                "TimescaleDB DSN is not configured – skipping write of %d row(s).",
                len(rows),
            )
            return

        now = datetime.now(UTC)
        records = [
            (
                now,
                row["tenant_id"],
                row["device_id"],
                row["metric_name"],
                float(row["value"]) if row.get("value") is not None else None,
                json.dumps(row.get("tags") or {}),
            )
            for row in rows
        ]

        try:
            pool = await self._get_pool()
            async with pool.acquire() as conn:
                await conn.executemany(_INSERT_SQL, records)
        except asyncpg.PostgresError as exc:
            raise TimescaleDBError(
                f"TimescaleDB write failed: {exc}"
            ) from exc

    async def close(self) -> None:
        """Close the connection pool gracefully."""
        if self._pool is not None:
            await self._pool.close()
            self._pool = None
