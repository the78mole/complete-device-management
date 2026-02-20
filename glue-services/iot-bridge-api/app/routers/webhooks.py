"""POST /webhooks/thingsboard – ThingsBoard Rule Engine webhook receiver.

ThingsBoard fires this endpoint (via a REST API Call node in the Rule Chain)
when a device first connects using its mTLS client certificate.

On receipt, the service:
1.  Extracts the device identifier from the event metadata.
2.  Checks whether a hawkBit target already exists (idempotency).
3.  Creates the hawkBit target if absent.
4.  Allocates a WireGuard VPN IP for the device (idempotent).
5.  Returns a JSON status payload that ThingsBoard can inspect.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException

from app.clients.hawkbit import HawkBitClient, HawkBitError
from app.clients.wireguard import WireGuardConfig
from app.deps import get_hawkbit_client, get_wg_config
from app.models import ThingsboardWebhookEvent, WebhookResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/webhooks", tags=["webhooks"])


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
