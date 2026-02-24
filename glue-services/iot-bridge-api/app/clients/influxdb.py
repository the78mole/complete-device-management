"""InfluxDB v2 HTTP write client.

Uses the InfluxDB v2 /api/v2/write endpoint (line protocol) via httpx so that
no additional Python package is needed beyond the existing httpx dependency.
"""

from __future__ import annotations

import logging

import httpx

logger = logging.getLogger(__name__)


class InfluxDBError(Exception):
    """Raised when an InfluxDB write operation fails."""


class InfluxDBClient:
    """Async client for the InfluxDB v2 line-protocol write endpoint."""

    def __init__(self, url: str, token: str, org: str, bucket: str) -> None:
        self._url = url.rstrip("/")
        self._token = token
        self._org = org
        self._bucket = bucket

    async def write_lines(self, lines: list[str]) -> None:
        """Write a batch of line-protocol strings to InfluxDB.

        Args:
            lines: Non-empty list of InfluxDB line protocol strings.

        Raises:
            InfluxDBError: on API failure or non-2xx response.
        """
        if not lines:
            return
        if not self._token:
            logger.warning(
                "InfluxDB token is not configured – skipping write of %d line(s).",
                len(lines),
            )
            return

        body = "\n".join(lines)
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self._url}/api/v2/write",
                params={
                    "org": self._org,
                    "bucket": self._bucket,
                    "precision": "ms",
                },
                headers={
                    "Authorization": f"Token {self._token}",
                    "Content-Type": "text/plain; charset=utf-8",
                },
                content=body.encode(),
                timeout=10.0,
            )
        if not resp.is_success:
            raise InfluxDBError(
                f"InfluxDB write failed (HTTP {resp.status_code}): {resp.text}"
            )
