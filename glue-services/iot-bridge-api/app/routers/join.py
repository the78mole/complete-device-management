"""JOIN workflow router.

Handles the full tenant onboarding lifecycle:

  POST /portal/admin/join-request/{tenant_id}
       Unauthenticated – called by a Tenant-Stack IoT Bridge API on first boot.
       Stores the request (Sub-CA CSR + WireGuard pubkey) with status *pending*.

  GET  /portal/admin/join-requests
       CDM admin only.  Returns all pending/approved/rejected requests.

  POST /portal/admin/tenants/{tenant_id}/approve
       CDM admin only.  Signs the Sub-CA CSR, provisions RabbitMQ, registers the
       Tenant Keycloak as an IdP in the cdm realm, and returns the bundle.

  POST /portal/admin/tenants/{tenant_id}/reject
       CDM admin only.  Marks the request as rejected with an optional reason.

  GET  /portal/admin/tenants/{tenant_id}/join-status
       Unauthenticated – tenant polls this endpoint until status is not *pending*.
       Returns the provisioning bundle once approved.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from typing import Any, cast

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse

from app.clients.join_store import load_store, save_store
from app.clients.rabbitmq import RabbitMQClient
from app.clients.step_ca import StepCAAdminClient, StepCAClient, StepCAError
from app.config import Settings
from app.deps import get_settings
from app.models import (
    JoinApproveRequest,
    JoinRejectRequest,
    JoinRequestPayload,
    JoinStatusResponse,
)
from app.routers.admin_portal import (
    _get_cdm_admin,
    _kc_admin_token,
    _rabbitmq,
    _random_password,
    _step_ca_admin,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/portal/admin", tags=["join"])


# ─────────────────────────────────────────────────────────────────────────────
# Join-request store helpers
# ─────────────────────────────────────────────────────────────────────────────

async def _get_request(tenant_id: str, settings: Settings) -> dict[str, Any]:
    """Return a single JOIN request by tenant_id, or raise 404."""
    store = await load_store(settings)
    entry = store.get(tenant_id)
    if not entry:
        raise HTTPException(
            status_code=404, detail=f"No JOIN request found for tenant '{tenant_id}'"
        )
    return cast(dict[str, Any], entry)


# ─────────────────────────────────────────────────────────────────────────────
# Keycloak helpers (IdP federation)
# ─────────────────────────────────────────────────────────────────────────────

async def _kc_create_federation_client(
    tenant_id: str,
    tenant_keycloak_url: str,
    token: str,
    settings: Settings,
) -> tuple[str, str]:
    """Create an OIDC client in the Provider ``cdm`` realm for Tenant-KC federation.

    The **Provider Keycloak** ``cdm`` realm will be registered as an Identity Provider
    in the **Tenant Keycloak** realm.  The Tenant KC needs an OIDC client registered on
    the Provider side so that Keycloak can validate the federation requests.

    The redirect URI is set to the Tenant KC broker callback endpoint so the
    Provider KC accepts login redirects from the Tenant KC.

    Args:
        tenant_id:           Tenant identifier – used as the client ID suffix.
        tenant_keycloak_url: External Keycloak base URL of the Tenant-Stack
                             (browser-accessible), e.g. ``https://tenant.example.com/auth``.
                             If empty, a wildcard redirect URI is used instead.
        token:               Provider Keycloak master-realm admin token.
        settings:            Application settings.

    Returns:
        ``(client_id, client_secret)`` of the newly created OIDC client.
    """
    kc_base = settings.keycloak_url.rstrip("/")
    client_id = f"cdm-federation-{tenant_id}"
    client_secret = _random_password()

    # The Tenant KC broker endpoint receives the token after the user authenticates
    # against the Provider KC.  Keycloak constructs it as:
    #   {tenant_keycloak_url}/realms/{tenant_id}/broker/cdm-provider/endpoint
    if tenant_keycloak_url:
        broker_callback = (
            f"{tenant_keycloak_url.rstrip('/')}/realms/{tenant_id}"
            "/broker/cdm-provider/endpoint"
        )
        redirect_uris = [broker_callback, broker_callback + "/*"]
    else:
        redirect_uris = ["*"]

    payload = {
        "clientId": client_id,
        "name": f"CDM Federation – {tenant_id}",
        "description": (
            "OIDC client used by the Tenant Keycloak to federate against the CDM Provider."
        ),
        "enabled": True,
        "protocol": "openid-connect",
        "publicClient": False,
        "secret": client_secret,
        "redirectUris": redirect_uris,
        "webOrigins": ["+"],
        "standardFlowEnabled": True,
        "implicitFlowEnabled": False,
        "directAccessGrantsEnabled": False,
        "serviceAccountsEnabled": False,
    }
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.post(
            f"{kc_base}/admin/realms/cdm/clients",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=15.0,
        )
    if resp.status_code == 409:
        logger.info("Keycloak federation client '%s' already exists – skipping.", client_id)
        # Return what we generated; the real secret may differ, but the Tenant Admin can
        # regenerate it in the Provider Keycloak UI if needed.
        return client_id, client_secret
    if not resp.is_success:
        raise HTTPException(
            status_code=502,
            detail=(
                f"Keycloak federation client creation failed HTTP"
                f" {resp.status_code}: {resp.text[:300]}"
            ),
        )
    logger.info(
        "Keycloak federation client '%s' created in Provider cdm realm.", client_id
    )
    return client_id, client_secret


async def _fetch_root_ca_cert(settings: Settings) -> str:
    """Fetch the Provider Root CA certificate PEM from step-ca."""
    ca_url = settings.step_ca_url.rstrip("/")
    fingerprint = settings.step_ca_fingerprint
    if not fingerprint:
        return ""
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.get(
            f"{ca_url}/1.0/root/{fingerprint}",
            timeout=10.0,
        )
        if not resp.is_success:
            logger.warning("Could not fetch root CA cert from step-ca: HTTP %s", resp.status_code)
            return ""
    return str(resp.json().get("ca", ""))


def _step_ca_client(settings: Settings) -> StepCAClient:
    """Instantiate a StepCAClient using the iot-bridge JWK provisioner credentials."""
    return StepCAClient(
        ca_url=settings.step_ca_url,
        provisioner_name=settings.step_ca_provisioner_name,
        provisioner_password=settings.step_ca_provisioner_password,
        root_fingerprint=settings.step_ca_fingerprint,
        verify_tls=settings.step_ca_verify_tls,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Endpoints
# ─────────────────────────────────────────────────────────────────────────────

@router.post(
    "/join-request/{tenant_id}",
    summary="Submit a JOIN request (called by Tenant-Stack, no auth required)",
)
async def submit_join_request(
    tenant_id: str,
    payload: JoinRequestPayload,
    request: Request,
) -> JSONResponse:
    """Receive a JOIN request from a Tenant-Stack and store it as *pending*.

    This endpoint is intentionally **unauthenticated** so that a freshly booted
    Tenant-Stack can register itself without a pre-shared secret.  The Provider
    Admin manually reviews and approves or rejects each request via the admin UI.
    """
    settings: Settings = get_settings()

    # Validate tenant_id format: lowercase alphanumeric + hyphens only
    if not tenant_id.replace("-", "").isalnum() or not tenant_id.islower():
        raise HTTPException(
            status_code=422,
            detail="tenant_id must be lowercase alphanumeric with optional hyphens",
        )

    store = await load_store(settings)
    if tenant_id in store and store[tenant_id].get("status") == "approved":
        raise HTTPException(
            status_code=409,
            detail=f"Tenant '{tenant_id}' is already approved.",
        )

    store[tenant_id] = {
        "tenant_id": tenant_id,
        "display_name": payload.display_name,
        "sub_ca_csr": payload.sub_ca_csr,
        "mqtt_bridge_csr": payload.mqtt_bridge_csr,
        "wg_pubkey": payload.wg_pubkey,
        "keycloak_url": payload.keycloak_url,
        "status": "pending",
        "requested_at": datetime.now(UTC).isoformat(),
        "approved_at": None,
        "rejected_at": None,
        "rejected_reason": None,
        "signed_cert": None,
        "root_ca_cert": None,
        "rabbitmq_url": None,
        "rabbitmq_vhost": None,
        "rabbitmq_user": None,
        "mqtt_bridge_cert": None,
        "cdm_idp_client_id": None,
        "cdm_idp_client_secret": None,
        "cdm_discovery_url": None,
        "wg_server_pubkey": None,
        "wg_server_endpoint": None,
        "wg_client_ip": None,
    }
    await save_store(store, settings)

    logger.info("JOIN request from tenant '%s' stored as pending.", tenant_id)
    return JSONResponse(
        status_code=202,
        content={
            "status": "pending",
            "tenant_id": tenant_id,
            "message": "JOIN request received. Awaiting Provider Admin approval.",
            "poll_url": f"/portal/admin/tenants/{tenant_id}/join-status",
        },
    )


@router.get(
    "/join-requests",
    summary="List all JOIN requests (CDM admin only)",
)
async def list_join_requests(request: Request) -> JSONResponse:
    """Return all JOIN requests (pending, approved, and rejected)."""
    _get_cdm_admin(request)
    settings: Settings = get_settings()
    store = await load_store(settings)

    # Return them ordered by requested_at descending
    entries = sorted(
        store.values(),
        key=lambda e: e.get("requested_at", ""),
        reverse=True,
    )
    return JSONResponse({"join_requests": entries, "total": len(entries)})


@router.post(
    "/tenants/{tenant_id}/approve",
    summary="Approve a JOIN request and provision all infrastructure (CDM admin only)",
)
async def approve_join_request(
    tenant_id: str,
    body: JoinApproveRequest,
    request: Request,
) -> JSONResponse:
    """Sign the Sub-CA CSR, provision RabbitMQ, create Keycloak federation client.

    The Keycloak federation direction is:
      Provider KC (cdm realm) → IdP registered in Tenant KC

    The Provider API creates an OIDC client in its own ``cdm`` realm and returns
    the credentials in the bundle.  The Tenant-Stack's ``init-sub-ca.sh`` then
    configures its Keycloak to use Provider KC as an Identity Provider, allowing
    CDM Admins to log directly into Tenant services.

    Returns the full provisioning bundle to be installed on the Tenant-Stack.
    """
    _get_cdm_admin(request)
    settings: Settings = get_settings()

    entry = await _get_request(tenant_id, settings)
    if entry["status"] == "approved":
        raise HTTPException(status_code=409, detail="Already approved.")
    if entry["status"] == "rejected":
        raise HTTPException(
            status_code=409,
            detail="Request was rejected. Reset it before approving.",
        )

    errors: dict[str, str] = {}
    results: dict[str, str] = {}

    # ── 1. Sign Sub-CA CSR ────────────────────────────────────────────────────
    signed_cert = ""
    root_ca_cert = ""
    try:
        sca_admin: StepCAAdminClient = _step_ca_admin(settings)
        signed_cert, root_ca_cert = await sca_admin.sign_sub_ca_csr(
            csr_pem=entry["sub_ca_csr"],
            tenant_id=tenant_id,
            sub_ca_provisioner_name=settings.step_ca_sub_ca_provisioner,
            sub_ca_provisioner_password=settings.step_ca_sub_ca_password,
        )
        # If root_ca_cert is just the issuer chain (may only be root),
        # also try to fetch it from step-ca directly for completeness.
        if not root_ca_cert:
            root_ca_cert = await _fetch_root_ca_cert(settings)
        results["step_ca"] = "signed"
        logger.info("Sub-CA CSR for tenant '%s' signed successfully.", tenant_id)
    except StepCAError as exc:
        errors["step_ca"] = str(exc)
        logger.error("Sub-CA CSR signing failed for '%s': %s", tenant_id, exc)

    # ── 2. Provision RabbitMQ vHost ───────────────────────────────────────────
    # The MQTT bridge authenticates via mTLS (EXTERNAL mechanism).  The RabbitMQ
    # username is the certificate CN (e.g. "acme-devices-mqtt-bridge").
    # No password is generated or stored.
    rmq_vhost = tenant_id
    rmq_url = settings.rabbitmq_mgmt_url
    rmq_mqtt_user = f"{tenant_id}-mqtt-bridge"
    try:
        rmq: RabbitMQClient = _rabbitmq(settings)
        # Create tenant vHost for device telemetry
        await rmq.create_vhost(rmq_vhost)
        # Create an EXTERNAL-auth user (empty password – cert CN is the credential)
        await rmq.create_user(rmq_mqtt_user, "", tags="none")
        await rmq.set_permissions(rmq_mqtt_user, rmq_vhost)
        results["rabbitmq"] = "provisioned"
        logger.info(
            "RabbitMQ tenant '%s' provisioned (user: %s, EXTERNAL auth).",
            tenant_id,
            rmq_mqtt_user,
        )
    except Exception as exc:  # noqa: BLE001
        errors["rabbitmq"] = str(exc)
        logger.error("RabbitMQ provisioning failed for '%s': %s", tenant_id, exc)

    # ── 2b. Sign MQTT bridge client certificate ──────────────────────────────
    mqtt_bridge_cert = ""
    mqtt_bridge_csr = entry.get("mqtt_bridge_csr", "")
    if mqtt_bridge_csr:
        try:
            sca_client: StepCAClient = _step_ca_client(settings)
            mqtt_bridge_cert, _ = await sca_client.sign_certificate(
                csr_pem=mqtt_bridge_csr,
                subject=rmq_mqtt_user,
                sans=[rmq_mqtt_user],
            )
            results["mqtt_bridge_cert"] = "signed"
            logger.info(
                "MQTT bridge cert for tenant '%s' signed (CN=%s).", tenant_id, rmq_mqtt_user
            )
        except StepCAError as exc:
            errors["mqtt_bridge_cert"] = str(exc)
            logger.error("MQTT bridge cert signing failed for '%s': %s", tenant_id, exc)
    else:
        results["mqtt_bridge_cert"] = "skipped (no mqtt_bridge_csr provided)"

    # ── 3. Create Keycloak federation client in Provider cdm realm ───────────
    # Creates an OIDC client that the Tenant Keycloak uses when registering
    # Provider KC as an Identity Provider.  CDM Admins can then log into Tenant
    # services (ThingsBoard, Grafana) via Provider Keycloak SSO.
    tenant_kc_url = entry.get("keycloak_url", "")
    cdm_idp_client_id = ""
    cdm_idp_client_secret = ""
    cdm_discovery_url = (
        f"{settings.external_url.rstrip('/')}/auth/realms/cdm"
        "/.well-known/openid-configuration"
    )
    try:
        token = await _kc_admin_token(settings)
        cdm_idp_client_id, cdm_idp_client_secret = await _kc_create_federation_client(
            tenant_id=tenant_id,
            tenant_keycloak_url=tenant_kc_url,
            token=token,
            settings=settings,
        )
        results["keycloak_federation"] = "client_created"
        logger.info(
            "Keycloak federation client '%s' created for tenant '%s'.",
            cdm_idp_client_id, tenant_id,
        )
    except Exception as exc:  # noqa: BLE001
        errors["keycloak_federation"] = str(exc)
        logger.error("Keycloak federation client creation failed for '%s': %s", tenant_id, exc)

    # ── 4. Persist the provisioning bundle ────────────────────────────────────
    store = await load_store(settings)
    store[tenant_id].update(
        {
            "status": "approved",
            "approved_at": datetime.now(UTC).isoformat(),
            "signed_cert": signed_cert,
            "root_ca_cert": root_ca_cert,
            "rabbitmq_url": rmq_url,
            "rabbitmq_vhost": rmq_vhost,
            "rabbitmq_user": rmq_mqtt_user,
            "mqtt_bridge_cert": mqtt_bridge_cert,
            "cdm_idp_client_id": cdm_idp_client_id,
            "cdm_idp_client_secret": cdm_idp_client_secret,
            "cdm_discovery_url": cdm_discovery_url,
        }
    )
    await save_store(store, settings)

    return JSONResponse(
        {
            "tenant_id": tenant_id,
            "status": "approved",
            "results": results,
            "errors": errors,
            # Return the full bundle so the admin can copy-paste or pipe to the tenant
            "bundle": {
                "signed_cert": signed_cert,
                "root_ca_cert": root_ca_cert,
                "rabbitmq_url": rmq_url,
                "rabbitmq_vhost": rmq_vhost,
                "rabbitmq_user": rmq_mqtt_user,
                "mqtt_bridge_cert": mqtt_bridge_cert,
                "cdm_idp_client_id": cdm_idp_client_id,
                "cdm_idp_client_secret": cdm_idp_client_secret,
                "cdm_discovery_url": cdm_discovery_url,
            },
        }
    )


@router.post(
    "/tenants/{tenant_id}/reject",
    summary="Reject a JOIN request (CDM admin only)",
)
async def reject_join_request(
    tenant_id: str,
    body: JoinRejectRequest,
    request: Request,
) -> JSONResponse:
    """Mark a pending JOIN request as rejected."""
    _get_cdm_admin(request)
    settings: Settings = get_settings()

    entry = await _get_request(tenant_id, settings)
    if entry["status"] == "approved":
        raise HTTPException(status_code=409, detail="Cannot reject an already approved request.")

    store = await load_store(settings)
    store[tenant_id].update(
        {
            "status": "rejected",
            "rejected_at": datetime.now(UTC).isoformat(),
            "rejected_reason": body.reason or "Rejected by provider admin.",
        }
    )
    await save_store(store, settings)

    logger.info("JOIN request for tenant '%s' rejected: %s", tenant_id, body.reason)
    return JSONResponse({"tenant_id": tenant_id, "status": "rejected"})


@router.get(
    "/tenants/{tenant_id}/join-status",
    response_model=JoinStatusResponse,
    summary="Poll JOIN request status (called by Tenant-Stack, no auth required)",
)
async def get_join_status(tenant_id: str, request: Request) -> JoinStatusResponse:
    """Return current JOIN status and provisioning bundle (once approved).

    The Tenant-Stack calls this endpoint every 60 s after submitting a JOIN
    request until the status changes from *pending*.
    """
    settings: Settings = get_settings()
    entry = await _get_request(tenant_id, settings)

    return JoinStatusResponse(
        tenant_id=tenant_id,
        status=entry["status"],
        signed_cert=entry.get("signed_cert"),
        root_ca_cert=entry.get("root_ca_cert"),
        rabbitmq_url=entry.get("rabbitmq_url"),
        rabbitmq_vhost=entry.get("rabbitmq_vhost"),
        rabbitmq_user=entry.get("rabbitmq_user"),
        mqtt_bridge_cert=entry.get("mqtt_bridge_cert"),
        cdm_idp_client_id=entry.get("cdm_idp_client_id"),
        cdm_idp_client_secret=entry.get("cdm_idp_client_secret"),
        cdm_discovery_url=entry.get("cdm_discovery_url"),
        wg_server_pubkey=entry.get("wg_server_pubkey"),
        wg_server_endpoint=entry.get("wg_server_endpoint"),
        wg_client_ip=entry.get("wg_client_ip"),
        rejected_reason=entry.get("rejected_reason"),
    )
