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


# ── JOIN workflow ─────────────────────────────────────────────────────────────


class JoinRequestPayload(BaseModel):
    """Payload posted by a Tenant-Stack IoT Bridge API to request platform JOIN."""

    display_name: str = Field(..., description="Human-readable tenant name, e.g. 'Acme Devices GmbH'")
    sub_ca_csr: str = Field(..., description="PEM-encoded PKCS#10 CSR for the Tenant Sub-CA")
    wg_pubkey: str = Field(..., description="WireGuard server public key of the Tenant-Stack")
    keycloak_url: str = Field("", description="External Keycloak URL of the Tenant-Stack (e.g. https://tenant.example.com/auth)")
    mqtt_bridge_csr: str = Field("", description="PEM-encoded PKCS#10 CSR for the Tenant MQTT bridge client certificate (mTLS auth)")


class JoinApproveRequest(BaseModel):
    """Optional body for the approve endpoint (currently reserved for future parameters)."""
    pass


class JoinRejectRequest(BaseModel):
    """Body for the reject endpoint."""
    reason: str = Field("", description="Human-readable rejection reason shown to the tenant")


class JoinStatusResponse(BaseModel):
    """Returned when the Tenant-Stack polls for JOIN request status."""

    tenant_id: str
    status: str = Field(..., description="pending | approved | rejected")
    # Populated after approval:
    signed_cert: str | None = Field(None, description="Signed Sub-CA certificate (PEM)")
    root_ca_cert: str | None = Field(None, description="Provider Root CA certificate (PEM)")
    rabbitmq_url: str | None = None
    rabbitmq_vhost: str | None = None
    rabbitmq_user: str | None = None
    # Signed MQTT bridge client certificate (PEM); private key stays on the Tenant-Stack.
    # Authentication is via mTLS – cert CN ({tenant_id}-mqtt-bridge) maps to RabbitMQ
    # username through EXTERNAL auth mechanism.  No password is issued.
    mqtt_bridge_cert: str | None = Field(None, description="Signed MQTT bridge client certificate (PEM)")
    # Keycloak federation: Provider cdm realm → registered as IdP in Tenant KC.
    # The Tenant-Stack configures its Keycloak to use Provider KC as an Identity Provider,
    # allowing CDM Admins to log into Tenant services (ThingsBoard, Grafana, etc.) via SSO.
    cdm_idp_client_id: str | None = Field(None, description="OIDC client ID registered in Provider cdm realm (for Tenant KC IdP)")
    cdm_idp_client_secret: str | None = Field(None, description="OIDC client secret – configure in Tenant Keycloak IdP settings")
    cdm_discovery_url: str | None = Field(None, description="Provider cdm realm OIDC discovery URL (browser-accessible)")
    wg_server_pubkey: str | None = None
    wg_server_endpoint: str | None = None
    wg_client_ip: str | None = None
    # Populated after rejection:
    rejected_reason: str | None = None
