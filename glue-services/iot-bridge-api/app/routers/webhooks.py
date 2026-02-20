"""POST /webhooks/thingsboard – ThingsBoard Rule Engine webhook receiver.

ThingsBoard fires this endpoint (via a REST API Call node in the Rule Chain)
when a device first connects using its mTLS client certificate.

On receipt, the service:
1.  Extracts the device identifier from the event metadata.
2.  Checks whether a hawkBit target already exists (idempotency).
3.  Creates the hawkBit target if absent.
4.  Allocates a WireGuard VPN IP for the device (idempotent).
5.  Returns a JSON status payload that ThingsBoard can inspect.

POST /webhooks/thingsboard/telemetry receives POST_TELEMETRY_REQUEST events and
writes the device metrics to InfluxDB with tenant and device_id tags for
multi-tenant data isolation.
"""

from __future__ import annotations

import logging
import re
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException

from app.clients.hawkbit import HawkBitClient, HawkBitError
from app.clients.influxdb import InfluxDBClient, InfluxDBError
from app.clients.wireguard import WireGuardConfig
from app.deps import get_hawkbit_client, get_influxdb_client, get_wg_config
from app.models import (
    TelemetryWebhookResponse,
    ThingsboardWebhookEvent,
    WebhookResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/webhooks", tags=["webhooks"])

# ── Helpers ────────────────────────────────────────────────────────────────────

# Characters that are invalid in InfluxDB tag values (spaces, commas, equals, backslash)
_TAG_UNSAFE_CHARS_RE = re.compile(r"[^A-Za-z0-9_\-.]")


def _safe_tag(value: str) -> str:
    """Escape a string for use as an InfluxDB tag value (no spaces or commas)."""
    return _TAG_UNSAFE_CHARS_RE.sub("_", value)


def _build_line_protocol(
    measurement: str,
    tags: dict[str, str],
    fields: dict[str, Any],
    timestamp_ms: int | None = None,
) -> str | None:
    """Build a single InfluxDB v2 line-protocol string.

    Returns ``None`` if *fields* is empty (InfluxDB requires at least one field).
    """
    field_parts: list[str] = []
    for key, val in fields.items():
        if isinstance(val, bool):
            field_parts.append(f"{key}={str(val).lower()}")
        elif isinstance(val, int):
            field_parts.append(f"{key}={val}i")
        elif isinstance(val, float):
            field_parts.append(f"{key}={val}")
        elif isinstance(val, str):
            escaped = val.replace("\\", "\\\\").replace('"', '\\"')
            field_parts.append(f'{key}="{escaped}"')

    if not field_parts:
        return None

    tag_str = ",".join(
        f"{k}={_safe_tag(v)}" for k, v in sorted(tags.items()) if v
    )
    ts_suffix = f" {timestamp_ms}" if timestamp_ms is not None else ""
    return f"{measurement},{tag_str} {','.join(field_parts)}{ts_suffix}"


def _extract_device_id(event: ThingsboardWebhookEvent) -> str | None:
    """Best-effort extraction of a stable device identifier from the event."""
    meta = event.metadata
    # ThingsBoard populates different fields depending on rule chain configuration
    for key in ("deviceId", "clientId", "deviceName"):
        value = meta.get(key)
        if value:
            return str(value)
    return None


@router.post(
    "/thingsboard",
    response_model=WebhookResponse,
    summary="ThingsBoard device-connected webhook",
    description=(
        "Triggered by the ThingsBoard Rule Engine when a device first "
        "connects via mTLS.  Creates the hawkBit target and assigns a "
        "WireGuard IP if not already provisioned."
    ),
)
async def thingsboard_webhook(
    event: ThingsboardWebhookEvent,
    hawkbit: HawkBitClient = Depends(get_hawkbit_client),
    wg: WireGuardConfig = Depends(get_wg_config),
) -> WebhookResponse:
    """Handle a ThingsBoard device-connected event."""
    device_id = _extract_device_id(event)
    if not device_id:
        logger.warning("Webhook received with no identifiable device_id: %s", event)
        return WebhookResponse(
            status="ignored",
            reason="No device_id found in event metadata",
        )

    device_name = event.metadata.get("deviceName", device_id)
    device_type = event.metadata.get("deviceType", "generic")

    # ── Idempotency check ────────────────────────────────────────────────────
    try:
        existing = await hawkbit.get_target(device_id)
    except httpx.RequestError as exc:
        raise HTTPException(
            status_code=503, detail=f"hawkBit unreachable: {exc}"
        ) from exc
    except HawkBitError as exc:
        raise HTTPException(
            status_code=502, detail=f"hawkBit query failed: {exc}"
        ) from exc

    if existing:
        logger.info("Device %s already provisioned in hawkBit – skipping.", device_id)
        wg_ip = wg.allocate_ip(device_id)  # idempotent – returns existing allocation
        return WebhookResponse(
            status="already_provisioned",
            device_id=device_id,
            wireguard_ip=wg_ip,
        )

    # ── Create hawkBit target ────────────────────────────────────────────────
    try:
        await hawkbit.create_target(
            controller_id=device_id,
            name=device_name,
            attributes={"device_type": device_type, "source": "thingsboard_webhook"},
        )
    except httpx.RequestError as exc:
        raise HTTPException(
            status_code=503, detail=f"hawkBit unreachable: {exc}"
        ) from exc
    except HawkBitError as exc:
        raise HTTPException(
            status_code=502, detail=f"hawkBit provisioning failed: {exc}"
        ) from exc

    logger.info("Created hawkBit target for device %s.", device_id)

    # ── Allocate WireGuard IP ────────────────────────────────────────────────
    wg_ip = wg.allocate_ip(device_id)
    logger.info("Assigned WireGuard IP %s to device %s.", wg_ip, device_id)

    return WebhookResponse(
        status="provisioned",
        device_id=device_id,
        wireguard_ip=wg_ip,
    )


@router.post(
    "/thingsboard/telemetry",
    response_model=TelemetryWebhookResponse,
    summary="ThingsBoard device telemetry webhook",
    description=(
        "Receives POST_TELEMETRY_REQUEST events from the ThingsBoard Rule Engine "
        "and writes the metrics to InfluxDB with tenant_id and device_id tags "
        "to enforce multi-tenant data isolation."
    ),
)
async def thingsboard_telemetry(
    event: ThingsboardWebhookEvent,
    influx: InfluxDBClient = Depends(get_influxdb_client),
) -> TelemetryWebhookResponse:
    """Write device telemetry from ThingsBoard to InfluxDB.

    Extracts tenant and device identifiers from the ThingsBoard metadata and
    adds them as InfluxDB tags so that each tenant's data is stored separately.
    """
    device_id = _extract_device_id(event)
    if not device_id:
        logger.warning(
            "Telemetry webhook received with no identifiable device_id: %s", event
        )
        return TelemetryWebhookResponse(
            status="ignored",
            reason="No device_id found in event metadata",
        )

    tenant_id = str(event.metadata.get("tenantId", "unknown"))

    # ── Build InfluxDB tags (tenant isolation) ───────────────────────────────
    tags = {
        "tenant_id": tenant_id,
        "device_id": device_id,
    }

    # ── Extract numeric / string fields from payload data ───────────────────
    data = event.data if isinstance(event.data, dict) else {}
    line = _build_line_protocol(
        measurement="device_telemetry",
        tags=tags,
        fields=data,
    )
    if line is None:
        return TelemetryWebhookResponse(
            status="ignored",
            device_id=device_id,
            tenant_id=tenant_id,
            reason="No numeric or string fields in telemetry payload",
        )

    # ── Write to InfluxDB ────────────────────────────────────────────────────
    try:
        await influx.write_lines([line])
    except InfluxDBError as exc:
        logger.error(
            "Failed to write telemetry for device %s (tenant %s) to InfluxDB: %s",
            device_id,
            tenant_id,
            exc,
        )
        raise HTTPException(
            status_code=503,
            detail=f"InfluxDB write failed: {exc}",
        ) from exc

    logger.debug(
        "Wrote telemetry for device %s (tenant %s) to InfluxDB.", device_id, tenant_id
    )
    return TelemetryWebhookResponse(
        status="written",
        device_id=device_id,
        tenant_id=tenant_id,
        points_written=1,
    )
