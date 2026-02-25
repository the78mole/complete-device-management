"""RabbitMQ Management HTTP API client.

Used by the admin portal to provision per-tenant virtual hosts and users
so that tenants are fully isolated on the message broker.

RabbitMQ Management Plugin API reference:
  https://rawcdn.githack.com/rabbitmq/rabbitmq-management/v3.12.0/priv/www/api/index.html

Access model
────────────
  • One vHost per tenant  (e.g. ``/tenant1``)
  • One RabbitMQ user per tenant (username = tenant id, random password)
  • User has full permissions on its own vHost, NO access to others
  • Platform internal services use the default admin user / vHost ``/``
"""

from __future__ import annotations

import logging
from typing import cast

import httpx

logger = logging.getLogger(__name__)


class RabbitMQError(Exception):
    """Raised when the RabbitMQ Management API returns an unexpected response."""


class RabbitMQClient:
    """Async client for the RabbitMQ Management HTTP API."""

    def __init__(self, mgmt_url: str, admin_user: str, admin_password: str) -> None:
        self._base = mgmt_url.rstrip("/") + "/api"
        self._auth = (admin_user, admin_password)

    # ── vHost management ─────────────────────────────────────────────────────

    async def list_vhosts(self) -> list[dict]:
        """Return all virtual hosts."""
        async with httpx.AsyncClient(verify=False) as client:
            resp = await client.get(f"{self._base}/vhosts", auth=self._auth, timeout=10)
            self._raise_for_status(resp, "list vhosts")
        return cast(list[dict], resp.json())

    async def create_vhost(self, name: str) -> None:
        """Create a virtual host.  Idempotent – no error if it already exists."""
        async with httpx.AsyncClient(verify=False) as client:
            resp = await client.put(
                f"{self._base}/vhosts/{_enc(name)}",
                auth=self._auth,
                json={"description": f"Tenant vHost: {name}"},
                timeout=10,
            )
        if resp.status_code not in (201, 204):
            self._raise_for_status(resp, f"create vhost '{name}'")
        logger.info("RabbitMQ vHost '%s' created/exists (HTTP %s)", name, resp.status_code)

    async def delete_vhost(self, name: str) -> None:
        """Delete a virtual host and all its queues/exchanges."""
        async with httpx.AsyncClient(verify=False) as client:
            resp = await client.delete(
                f"{self._base}/vhosts/{_enc(name)}",
                auth=self._auth,
                timeout=10,
            )
        if resp.status_code not in (204, 404):
            self._raise_for_status(resp, f"delete vhost '{name}'")
        logger.info("RabbitMQ vHost '%s' deleted (HTTP %s)", name, resp.status_code)

    # ── User management ──────────────────────────────────────────────────────

    async def list_users(self) -> list[dict]:
        """Return all RabbitMQ users."""
        async with httpx.AsyncClient(verify=False) as client:
            resp = await client.get(f"{self._base}/users", auth=self._auth, timeout=10)
            self._raise_for_status(resp, "list users")
        return cast(list[dict], resp.json())

    async def create_user(
        self,
        username: str,
        password: str,
        tags: str = "none",
    ) -> None:
        """Create (or update) a RabbitMQ user.

        Args:
            username: RabbitMQ username (typically the tenant ID).
            password: Plaintext password; RabbitMQ hashes it.
            tags:     Comma-separated RabbitMQ tags (``management``, ``administrator``, etc.).
        """
        async with httpx.AsyncClient(verify=False) as client:
            resp = await client.put(
                f"{self._base}/users/{_enc(username)}",
                auth=self._auth,
                json={"password": password, "tags": tags},
                timeout=10,
            )
        if resp.status_code not in (201, 204):
            self._raise_for_status(resp, f"create user '{username}'")
        logger.info("RabbitMQ user '%s' created/updated (HTTP %s)", username, resp.status_code)

    async def delete_user(self, username: str) -> None:
        """Delete a RabbitMQ user."""
        async with httpx.AsyncClient(verify=False) as client:
            resp = await client.delete(
                f"{self._base}/users/{_enc(username)}",
                auth=self._auth,
                timeout=10,
            )
        if resp.status_code not in (204, 404):
            self._raise_for_status(resp, f"delete user '{username}'")

    # ── Permissions ──────────────────────────────────────────────────────────

    async def set_permissions(
        self,
        username: str,
        vhost: str,
        configure: str = ".*",
        write: str = ".*",
        read: str = ".*",
    ) -> None:
        """Grant full permissions for *username* on *vhost*."""
        async with httpx.AsyncClient(verify=False) as client:
            resp = await client.put(
                f"{self._base}/permissions/{_enc(vhost)}/{_enc(username)}",
                auth=self._auth,
                json={"configure": configure, "write": write, "read": read},
                timeout=10,
            )
        if resp.status_code not in (201, 204):
            self._raise_for_status(resp, f"set permissions for '{username}' on '{vhost}'")
        logger.info("RabbitMQ permissions set: %s@%s", username, vhost)

    async def get_user_permissions(self, username: str) -> list[dict]:
        """Return all vHost permissions for a user."""
        async with httpx.AsyncClient(verify=False) as client:
            resp = await client.get(
                f"{self._base}/users/{_enc(username)}/permissions",
                auth=self._auth,
                timeout=10,
            )
        if resp.status_code == 404:
            return []
        self._raise_for_status(resp, f"get permissions for '{username}'")
        return cast(list[dict], resp.json())

    # ── Convenience: full tenant setup ──────────────────────────────────────

    async def provision_tenant(self, tenant_id: str, password: str) -> None:
        """Create vHost + user + permissions for a new tenant in one call."""
        await self.create_vhost(tenant_id)
        await self.create_user(tenant_id, password, tags="none")
        await self.set_permissions(tenant_id, tenant_id)
        logger.info("RabbitMQ tenant '%s' fully provisioned", tenant_id)

    async def deprovision_tenant(self, tenant_id: str) -> None:
        """Remove vHost + user for a tenant."""
        await self.delete_vhost(tenant_id)
        await self.delete_user(tenant_id)
        logger.info("RabbitMQ tenant '%s' removed", tenant_id)

    # ── Internal helpers ─────────────────────────────────────────────────────

    @staticmethod
    def _raise_for_status(resp: httpx.Response, action: str) -> None:
        if not resp.is_success:
            raise RabbitMQError(
                f"RabbitMQ API: {action} failed with HTTP {resp.status_code}: {resp.text[:200]}"
            )


def _enc(value: str) -> str:
    """Percent-encode a vHost or username for use in URL path segments.

    RabbitMQ Management API requires ``%2F`` for the default ``/`` vHost.
    """
    from urllib.parse import quote
    return quote(value, safe="")
