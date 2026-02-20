"""Pydantic request / response models for the IoT Bridge API."""

from typing import Any

from pydantic import BaseModel, Field

# ── Enrollment ────────────────────────────────────────────────────────────────

class EnrollmentRequest(BaseModel):
    """Payload sent by the factory / simulation tooling for a new device."""

    csr: str = Field(..., description="PEM-encoded PKCS#10 Certificate Signing Request")
    device_name: str = Field(..., description="Human-readable device name")
    device_type: str = Field("generic", description="Device type / model identifier")
    wg_public_key: str | None = Field(
        None, description="WireGuard public key (base64, 32 bytes) – optional"
    )


class EnrollmentResponse(BaseModel):
    """Returned to the factory tooling after successful enrollment."""

    certificate: str = Field(..., description="Signed leaf certificate (PEM)")
    ca_chain: str = Field(..., description="CA certificate chain (PEM)")
    wireguard_ip: str = Field(..., description="Assigned VPN IP address")
    wireguard_config: str = Field(..., description="Client-side WireGuard config (INI)")


# ── ThingsBoard webhook ───────────────────────────────────────────────────────

class ThingsboardWebhookEvent(BaseModel):
    """
    Generic ThingsBoard Rule Engine HTTP webhook payload.

    ThingsBoard sends flexible JSON; we capture the known fields and
    treat the rest as opaque metadata/data blobs.
    """

    msgType: str = Field("UNKNOWN", description="ThingsBoard message type")
    metadata: dict[str, Any] = Field(default_factory=dict)
    data: dict[str, Any] | str = Field(default_factory=dict)


class WebhookResponse(BaseModel):
    status: str
    device_id: str | None = None
    wireguard_ip: str | None = None
    reason: str | None = None


class TelemetryWebhookResponse(BaseModel):
    status: str
    device_id: str | None = None
    tenant_id: str | None = None
    points_written: int = 0
    reason: str | None = None


# ── Health ────────────────────────────────────────────────────────────────────

class HealthResponse(BaseModel):
    status: str = "ok"
    service: str = "iot-bridge-api"
