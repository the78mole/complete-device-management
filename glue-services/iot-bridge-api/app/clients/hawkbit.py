"""hawkBit REST API client.

Communicates with Eclipse hawkBit's Management REST API to create and query
software-update targets (one target per IoT device).
"""

from __future__ import annotations

from typing import Any

import httpx


class HawkBitError(Exception):
    """Raised when the hawkBit API returns an unexpected response."""


class HawkBitClient:
    """Async client for the Eclipse hawkBit Management REST API."""

    def __init__(self, base_url: str, username: str, password: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._auth = (username, password)

    async def get_target(self, controller_id: str) -> dict[str, Any] | None:
        """Return the hawkBit target for *controller_id*, or ``None`` if absent."""
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                f"{self._base_url}/rest/v1/targets/{controller_id}",
                auth=self._auth,
                timeout=10.0,
            )
        if resp.status_code == 404:
            return None
        if not resp.is_success:
            raise HawkBitError(
                f"hawkBit GET target returned {resp.status_code}: {resp.text}"
            )
        return resp.json()  # type: ignore[no-any-return]

    async def create_target(
        self,
        controller_id: str,
        name: str,
        attributes: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        """Create a new target in hawkBit.

        Args:
            controller_id: Unique device identifier (used as the DDI controller ID).
            name:          Human-readable device name shown in the hawkBit UI.
            attributes:    Optional key/value attributes attached to the target.

        Returns:
            The created target object returned by hawkBit.

        Raises:
            HawkBitError: on API failures.
        """
        payload: list[dict[str, Any]] = [{"controllerId": controller_id, "name": name}]
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                f"{self._base_url}/rest/v1/targets",
                json=payload,
                auth=self._auth,
                timeout=10.0,
            )
            if not resp.is_success:
                raise HawkBitError(
                    f"hawkBit POST targets returned {resp.status_code}: {resp.text}"
                )
            created: list[dict[str, Any]] = resp.json()

        target = created[0]

        if attributes:
            await self._put_attributes(controller_id, attributes)

        return target

    async def _put_attributes(
        self, controller_id: str, attributes: dict[str, str]
    ) -> None:
        """Attach key/value attributes to an existing target."""
        async with httpx.AsyncClient() as client:
            resp = await client.put(
                f"{self._base_url}/rest/v1/targets/{controller_id}/attributes",
                json=attributes,
                auth=self._auth,
                timeout=10.0,
            )
        if not resp.is_success:
            raise HawkBitError(
                f"hawkBit PUT attributes returned {resp.status_code}: {resp.text}"
            )
