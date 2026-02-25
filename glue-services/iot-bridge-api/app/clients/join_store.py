"""Persistent JSON store for tenant JOIN requests.

A single JSON file at ``settings.join_requests_db_path`` holds the state of
all tenant JOIN requests.  Access is guarded by an asyncio.Lock so concurrent
approve/reject calls cannot corrupt the file.

Structure::

    {                                                                                               
        "<tenant_id>": {
            "tenant_id":       "...",
            "display_name":    "...",
            "sub_ca_csr":      "-----BEGIN CERTIFICATE REQUEST-----\\n...",
            "mqtt_bridge_csr": "-----BEGIN CERTIFICATE REQUEST-----\\n...",  # optional
            "wg_pubkey":       "...",
            "keycloak_url":    "https://...",       # optional
            "status":          "pending|approved|rejected",
            "requested_at":    "ISO8601",
            "approved_at":     "ISO8601|null",
            "rejected_at":     "ISO8601|null",
            "rejected_reason": "...|null",
            "signed_cert":     "PEM|null",
            "root_ca_cert":    "PEM|null",
            "rabbitmq_url":    "http://...|null",
            "rabbitmq_vhost":  "...|null",
            "rabbitmq_user":   "...|null",         # CN of mqtt_bridge_cert
            "mqtt_bridge_cert": "PEM|null",        # signed by iot-bridge provisioner
            "cdm_idp_client_id": "...|null",       # OIDC client in Provider cdm realm
            "cdm_idp_client_secret": "...|null",   # → configure in Tenant KC IdP
            "cdm_discovery_url": "https://...|null",  # Provider cdm OIDC discovery URL
            "wg_server_pubkey": "...|null",
            "wg_server_endpoint": "...|null",
            "wg_client_ip":    "...|null"
        }
    }
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import Any, cast

from app.config import Settings

_store_lock: asyncio.Lock = asyncio.Lock()


def _store_path(settings: Settings) -> Path:
    return Path(settings.join_requests_db_path)


async def load_store(settings: Settings) -> dict[str, Any]:
    """Return the full JOIN-request dict from disk.  Returns {} if the file is missing."""
    path = _store_path(settings)
    if not path.exists():
        return {}
    async with _store_lock:
        return cast(dict[str, Any], json.loads(path.read_text()))


async def save_store(data: dict[str, Any], settings: Settings) -> None:
    """Persist the full JOIN-request dict to disk (atomic rename)."""
    path = _store_path(settings)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    async with _store_lock:
        tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False))
        tmp.replace(path)
