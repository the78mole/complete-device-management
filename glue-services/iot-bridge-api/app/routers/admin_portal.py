"""Admin Portal router — tenant lifecycle management.

Only accessible to users authenticated in the ``cdm`` realm with the
``cdm-admin`` or ``platform-admin`` role.

Routes
──────
  GET   /portal/admin/                    → Admin dashboard (HTML)
  POST  /portal/admin/tenants             → Create a new tenant
  DELETE /portal/admin/tenants/{id}       → Remove a tenant
  POST  /portal/admin/tenants/{id}/provisioner  → Add step-ca OIDC provisioner

Each modifying endpoint returns JSON so the dashboard can call them via fetch().

Tenant creation does the following in one call:
  1. Create Keycloak realm with default roles (cdm-admin/operator/viewer) and
     the ``portal`` OIDC client.
  2. Create RabbitMQ vHost + user + permissions (full isolation).
  3. Optionally registers an OIDC provisioner in step-ca for this tenant.
"""

from __future__ import annotations

import logging
import secrets
import string
from datetime import UTC, datetime
from typing import Any, cast

import httpx
from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

import app.clients.join_key_store as jks
from app.clients.join_store import load_store
from app.clients.rabbitmq import RabbitMQClient, RabbitMQError
from app.clients.step_ca import StepCAAdminClient, StepCAError
from app.config import Settings
from app.deps import get_settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/portal/admin", tags=["admin-portal"])
templates = Jinja2Templates(directory="app/templates")

ADMIN_ROLES = {"cdm-admin", "platform-admin"}

# ── Auth guard ───────────────────────────────────────────────────────────────


def _get_cdm_admin(request: Request) -> dict | None:
    """Return session user if authenticated as cdm realm admin, else None."""
    user = request.session.get("user")
    if not user:
        return None
    if user.get("realm") != "cdm":
        return None
    if not (set(user.get("roles", [])) & ADMIN_ROLES):
        return None
    return cast(dict[Any, Any], user)


async def _require_cdm_admin(request: Request) -> dict:
    """Require cdm-admin via portal session OR Bearer token.

    Checks the Starlette session first (portal login).  If no session is
    present, falls back to validating an ``Authorization: Bearer <token>``
    header via JWKS signature verification against the internal Keycloak URL.

    Using JWKS-based validation (instead of the /userinfo endpoint) avoids the
    Keycloak 26 breaking change where /userinfo requires an ``aud`` claim in the
    token that matches the calling client — a requirement that breaks tokens
    issued against an external URL (e.g. GitHub Codespaces) when the API calls
    the internal Docker hostname.

    Raises:
        HTTPException(401): No credentials provided or token invalid/expired.
        HTTPException(403): Credentials valid but role insufficient.
    """
    import json as _json

    from fastapi import HTTPException as _HTTPException  # local import to avoid circular
    from jwcrypto import jwk as _jwk
    from jwcrypto import jwt as _jwcjwt

    # 1. Portal session (server-side, most trusted)
    user = _get_cdm_admin(request)
    if user:
        return user

    # 2. Bearer token (Keycloak.js / dashboard client)
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        raise _HTTPException(status_code=401, detail="Authentication required")

    token = auth[7:]
    settings = get_settings()

    # Fetch JWKS from the internal Keycloak URL.
    # The JWKS public key is realm-specific but not URL-specific, so signature
    # verification succeeds even if the token's ``iss`` contains the external
    # Codespaces hostname rather than the internal Docker hostname.
    try:
        async with httpx.AsyncClient(verify=False) as http:
            resp = await http.get(
                f"{settings.keycloak_url}/realms/cdm/protocol/openid-connect/certs",
                timeout=10,
            )
        resp.raise_for_status()
        jwks_bytes = resp.content
    except Exception as err:
        logger.warning("Failed to fetch JWKS from Keycloak: %s", err)
        raise _HTTPException(status_code=401, detail="Unable to validate token") from err

    # Verify JWT signature using jwcrypto (checks signature + exp/nbf claims).
    try:
        key_set = _jwk.JWKSet()
        key_set.import_keyset(jwks_bytes)
        tok_obj = _jwcjwt.JWT(key=key_set, jwt=token)
        claims = _json.loads(tok_obj.claims)
    except Exception as err:
        raise _HTTPException(status_code=401, detail="Invalid or expired token") from err

    # KC 26: roles in realm_access.roles; some mappers also put them in flat "roles" claim
    roles: list[str] = claims.get("realm_access", {}).get("roles", []) or claims.get("roles", [])
    if not (set(roles) & ADMIN_ROLES):
        raise _HTTPException(
            status_code=403,
            detail="Access denied – cdm-admin or platform-admin role required",
        )

    return {
        "realm": "cdm",
        "roles": roles,
        "preferred_username": claims.get("preferred_username", ""),
    }


# ── Helper factories ─────────────────────────────────────────────────────────


def _rabbitmq(settings: Settings) -> RabbitMQClient:
    return RabbitMQClient(
        settings.rabbitmq_mgmt_url,
        settings.rabbitmq_admin_user,
        settings.rabbitmq_admin_password,
    )


def _step_ca_admin(settings: Settings) -> StepCAAdminClient:
    return StepCAAdminClient(
        settings.step_ca_url,
        settings.step_ca_admin_provisioner,
        settings.step_ca_admin_password,
        verify_tls=settings.step_ca_verify_tls,
    )


def _random_password(length: int = 24) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


# ── Keycloak helpers ─────────────────────────────────────────────────────────


async def _kc_admin_token(settings: Settings) -> str:
    """Obtain a Keycloak master-realm admin token (admin-cli)."""
    url = f"{settings.keycloak_url}/realms/master/protocol/openid-connect/token"
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.post(
            url,
            data={
                "client_id": "admin-cli",
                "grant_type": "password",
                "username": settings.keycloak_admin_user,
                "password": settings.keycloak_admin_password,
            },
            timeout=15,
        )
    if not resp.is_success:
        raise RuntimeError(f"KC admin token failed HTTP {resp.status_code}: {resp.text[:200]}")
    return str(resp.json()["access_token"])


async def _kc_realm_exists(realm_id: str, token: str, settings: Settings) -> bool:
    url = f"{settings.keycloak_url}/admin/realms/{realm_id}"
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=10)
    return resp.status_code == 200


async def _kc_fix_account_console(realm_id: str, token: str, settings: Settings) -> None:
    """Add the 'account' audience mapper to the account-console client.

    Without this mapper, the Account Console REST API returns 403 because the
    token's ``aud`` claim doesn't contain ``account``.
    """
    # Find account-console client ID
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.get(
            f"{settings.keycloak_url}/admin/realms/{realm_id}/clients?clientId=account-console",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
        )
    clients = resp.json() if resp.is_success else []
    if not clients:
        logger.warning("account-console client not found in realm '%s'", realm_id)
        return

    ac_id = clients[0]["id"]

    # Check if mapper already exists
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.get(
            f"{settings.keycloak_url}/admin/realms/{realm_id}/clients/{ac_id}/protocol-mappers/models",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
        )
    mappers = resp.json() if resp.is_success else []
    if any(m.get("config", {}).get("included.client.audience") == "account" for m in mappers):
        return  # already present

    mapper_payload = {
        "name": "account-audience",
        "protocol": "openid-connect",
        "protocolMapper": "oidc-audience-mapper",
        "consentRequired": False,
        "config": {
            "included.client.audience": "account",
            "id.token.claim": "false",
            "access.token.claim": "true",
        },
    }
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.post(
            f"{settings.keycloak_url}/admin/realms/{realm_id}/clients/{ac_id}/protocol-mappers/models",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json=mapper_payload,
            timeout=10,
        )
    if resp.status_code not in (201, 409):
        logger.warning(
            "Could not add account-audience mapper to realm '%s': HTTP %s",
            realm_id,
            resp.status_code,
        )
    else:
        logger.info(
            "account-audience mapper added to realm '%s' account-console (HTTP %s)",
            realm_id,
            resp.status_code,
        )


async def _kc_create_realm(
    realm_id: str, display_name: str, token: str, settings: Settings
) -> None:
    """Create a Keycloak realm with standard CDM roles and the portal OIDC client."""
    realm_payload = {
        "id": realm_id,
        "realm": realm_id,
        "displayName": display_name,
        "enabled": True,
        "sslRequired": "external",
        "registrationAllowed": False,
        "loginWithEmailAllowed": True,
        "duplicateEmailsAllowed": False,
        "resetPasswordAllowed": True,
        "editUsernameAllowed": False,
        "bruteForceProtected": True,
        "roles": {
            "realm": [
                {"name": "cdm-admin", "description": "Tenant administrator"},
                {"name": "cdm-operator", "description": "Fleet operator"},
                {"name": "cdm-viewer", "description": "Read-only access"},
            ]
        },
        "clients": [
            {
                "clientId": "portal",
                "name": "CDM Tenant Portal",
                "enabled": True,
                "protocol": "openid-connect",
                "publicClient": False,
                "secret": settings.portal_oidc_secret,
                "redirectUris": ["*"],
                "webOrigins": ["*"],
                "standardFlowEnabled": True,
                "implicitFlowEnabled": False,
                "directAccessGrantsEnabled": False,
                "postLogoutRedirectUris": ["*"],
            }
        ],
        "defaultDefaultClientScopes": ["profile", "email", "roles", "web-origins"],
        "defaultOptionalClientScopes": ["offline_access", "address", "phone"],
        "eventsEnabled": True,
        "eventsListeners": ["jboss-logging"],
        "adminEventsEnabled": True,
        "adminEventsDetailsEnabled": True,
    }
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.post(
            f"{settings.keycloak_url}/admin/realms",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json=realm_payload,
            timeout=20,
        )
    if resp.status_code not in (201, 409):
        raise RuntimeError(f"KC create realm failed HTTP {resp.status_code}: {resp.text[:300]}")
    logger.info("Keycloak realm '%s' created/exists (HTTP %s)", realm_id, resp.status_code)

    # Add account-audience mapper to account-console client (required for Account Console REST API)
    await _kc_fix_account_console(realm_id, token, settings)


async def _kc_create_user(
    realm_id: str,
    username: str,
    email: str,
    password: str,
    roles: list[str],
    token: str,
    settings: Settings,
) -> None:
    """Create a user in a Keycloak realm and assign realm roles."""
    user_payload = {
        "username": username,
        "email": email,
        "firstName": username.capitalize(),
        "lastName": "",
        "enabled": True,
        "emailVerified": True,
        "credentials": [{"type": "password", "value": password, "temporary": True}],
    }
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.post(
            f"{settings.keycloak_url}/admin/realms/{realm_id}/users",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json=user_payload,
            timeout=15,
        )
    if resp.status_code not in (201, 409):
        raise RuntimeError(f"KC create user failed HTTP {resp.status_code}: {resp.text[:300]}")

    if resp.status_code == 409:
        return  # user already exists

    user_url = resp.headers.get("Location", "")
    user_id = user_url.rstrip("/").split("/")[-1]

    # Fetch role IDs
    async with httpx.AsyncClient(verify=False) as client:
        roles_resp = await client.get(
            f"{settings.keycloak_url}/admin/realms/{realm_id}/roles",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
        )
    all_roles = roles_resp.json() if roles_resp.is_success else []
    role_objects = [r for r in all_roles if r["name"] in roles]

    if role_objects and user_id:
        async with httpx.AsyncClient(verify=False) as client:
            await client.post(
                f"{settings.keycloak_url}/admin/realms/{realm_id}/users/{user_id}/role-mappings/realm",
                headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
                json=role_objects,
                timeout=10,
            )


async def _kc_delete_realm(realm_id: str, token: str, settings: Settings) -> None:
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.delete(
            f"{settings.keycloak_url}/admin/realms/{realm_id}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=15,
        )
    if resp.status_code not in (204, 404):
        raise RuntimeError(f"KC delete realm failed HTTP {resp.status_code}")


async def _kc_list_realms(token: str, settings: Settings) -> list[dict]:
    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.get(
            f"{settings.keycloak_url}/admin/realms",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
        )
    return resp.json() if resp.is_success else []


# ── Routes ───────────────────────────────────────────────────────────────────


@router.get("/", response_class=HTMLResponse, name="admin_portal_dashboard")
async def admin_dashboard(
    request: Request,
    settings: Settings = Depends(get_settings),
):
    user = _get_cdm_admin(request)
    if not user:
        return RedirectResponse("/api/portal/", status_code=302)

    # Load aggregated state for the dashboard
    try:
        kc_token = await _kc_admin_token(settings)
        realms = await _kc_list_realms(kc_token, settings)
        # Filter out system realms
        system_realms = {"master"}
        tenant_realms = [r for r in realms if r["realm"] not in system_realms]
    except Exception as exc:
        logger.exception("Could not load Keycloak realms: %s", exc)
        tenant_realms = []

    try:
        rmq = _rabbitmq(settings)
        vhosts = await rmq.list_vhosts()
        vhost_names = {v["name"] for v in vhosts}
    except Exception as exc:
        logger.exception("Could not load RabbitMQ vHosts: %s", exc)
        vhost_names = set()

    try:
        step_admin = _step_ca_admin(settings)
        provisioners = await step_admin.list_provisioners()
        oidc_provisioner_names = {p["name"] for p in provisioners if p.get("type") == "OIDC"}
    except Exception as exc:
        logger.exception("Could not load step-ca provisioners: %s", exc)
        oidc_provisioner_names = set()

    # Load pending JOIN requests (from file-based store)
    try:
        join_store = await load_store(settings)
        join_requests = sorted(
            join_store.values(),
            key=lambda e: e.get("requested_at", ""),
            reverse=True,
        )
    except Exception as exc:
        logger.exception("Could not load JOIN requests: %s", exc)
        join_requests = []

    # Load prepared (but not yet joined) tenant slots from join_key_store
    try:
        all_keys = await jks.load_keys(settings)
        now = datetime.now(UTC)
        prepared_tenants = sorted(
            [
                e
                for e in all_keys.values()
                if e.get("status") == "open" and datetime.fromisoformat(e["expires_at"]) > now
            ],
            key=lambda e: e.get("created_at", ""),
            reverse=True,
        )
    except Exception as exc:
        logger.exception("Could not load JOIN keys: %s", exc)
        prepared_tenants = []

    return templates.TemplateResponse(
        request,
        "portal/admin_dashboard.html",
        {
            "user": user,
            "tenant_realms": tenant_realms,
            "vhost_names": list(vhost_names),
            "oidc_provisioner_names": list(oidc_provisioner_names),
            "external_url": settings.external_url,
            "keycloak_url": settings.keycloak_url.replace(
                "http://keycloak:8080", settings.external_url
            ),
            "join_requests": join_requests,
            "prepared_tenants": prepared_tenants,
        },
    )


@router.post("/tenants", name="admin_create_tenant")
async def create_tenant(
    request: Request,
    settings: Settings = Depends(get_settings),
):
    """Create a new tenant: Keycloak realm + RabbitMQ vHost.

    Expected JSON body:
        {
            "realm_id":     "tenant3",
            "display_name": "My Company GmbH",
            "admin_email":  "admin@mycompany.example.com",
            "admin_user":   "admin"           (optional, default = realm_id + "-admin")
        }
    """
    user = _get_cdm_admin(request)
    if not user:
        return JSONResponse({"error": "Unauthorized"}, status_code=403)

    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON body"}, status_code=400)

    realm_id = str(body.get("realm_id", "")).strip().lower()
    display_name = str(body.get("display_name", realm_id)).strip()
    admin_email = str(body.get("admin_email", f"admin@{realm_id}.local")).strip()
    admin_user = str(body.get("admin_user", f"{realm_id}-admin")).strip()

    if not realm_id or not realm_id.isidentifier():
        return JSONResponse(
            {"error": "realm_id must be a valid identifier (letters, digits, underscores)"},
            status_code=400,
        )

    protected = {"master", "cdm"}
    if realm_id in protected:
        return JSONResponse({"error": f"Realm '{realm_id}' is protected"}, status_code=400)

    results: dict[str, str] = {}
    errors: dict[str, str] = {}
    admin_password = _random_password()

    # 1. Keycloak realm
    try:
        kc_token = await _kc_admin_token(settings)
        await _kc_create_realm(realm_id, display_name, kc_token, settings)
        await _kc_create_user(
            realm_id, admin_user, admin_email, admin_password, ["cdm-admin"], kc_token, settings
        )
        results["keycloak"] = "created"
    except Exception as exc:
        logger.exception("Keycloak provisioning failed for '%s': %s", realm_id, exc)
        errors["keycloak"] = str(exc)

    # 2. RabbitMQ vHost
    try:
        rmq = _rabbitmq(settings)
        rmq_password = _random_password()
        await rmq.provision_tenant(realm_id, rmq_password)
        results["rabbitmq"] = "created"
        results["rabbitmq_user"] = realm_id
        results["rabbitmq_password"] = rmq_password
    except RabbitMQError as exc:
        logger.exception("RabbitMQ provisioning failed for '%s': %s", realm_id, exc)
        errors["rabbitmq"] = str(exc)

    return JSONResponse(
        {
            "realm_id": realm_id,
            "display_name": display_name,
            "admin_user": admin_user,
            "admin_email": admin_email,
            "admin_password": admin_password,
            "results": results,
            "errors": errors,
            "hint": (
                "Save the admin_password — it will not be shown again. "
                "The admin user must change it on first login (temporary=true)."
            ),
        }
    )


@router.delete("/tenants/{realm_id}", name="admin_delete_tenant")
async def delete_tenant(
    realm_id: str,
    request: Request,
    settings: Settings = Depends(get_settings),
):
    user = _get_cdm_admin(request)
    if not user:
        return JSONResponse({"error": "Unauthorized"}, status_code=403)

    protected = {"master", "cdm"}
    if realm_id in protected:
        return JSONResponse({"error": f"Realm '{realm_id}' is protected"}, status_code=400)

    results: dict[str, str] = {}
    errors: dict[str, str] = {}

    try:
        kc_token = await _kc_admin_token(settings)
        await _kc_delete_realm(realm_id, kc_token, settings)
        results["keycloak"] = "deleted"
    except Exception as exc:
        errors["keycloak"] = str(exc)

    try:
        rmq = _rabbitmq(settings)
        await rmq.deprovision_tenant(realm_id)
        results["rabbitmq"] = "deleted"
    except RabbitMQError as exc:
        errors["rabbitmq"] = str(exc)

    return JSONResponse({"realm_id": realm_id, "results": results, "errors": errors})


@router.post("/tenants/{realm_id}/provisioner", name="admin_add_provisioner")
async def add_oidc_provisioner(
    realm_id: str,
    request: Request,
    settings: Settings = Depends(get_settings),
):
    """Register an OIDC provisioner in step-ca for a tenant Keycloak realm.

    Expected JSON body:
        {
            "client_id":     "step-ca",
            "client_secret": "changeme",
            "admin_emails":  ["alice@acme.example.com"]   (optional)
        }
    """
    user = _get_cdm_admin(request)
    if not user:
        return JSONResponse({"error": "Unauthorized"}, status_code=403)

    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON body"}, status_code=400)

    client_id = str(body.get("client_id", "step-ca")).strip()
    client_secret = str(body.get("client_secret", "")).strip()
    admin_emails = body.get("admin_emails", [])

    # Build Keycloak OIDC discovery URL (internal URL for step-ca to resolve)
    configuration_endpoint = (
        f"{settings.keycloak_url}/realms/{realm_id}/.well-known/openid-configuration"
    )
    provisioner_name = f"{realm_id}-keycloak"

    try:
        step_admin = _step_ca_admin(settings)
        result = await step_admin.add_oidc_provisioner(
            name=provisioner_name,
            client_id=client_id,
            client_secret=client_secret,
            configuration_endpoint=configuration_endpoint,
            admin_emails=admin_emails or None,
        )
        return JSONResponse(
            {
                "realm_id": realm_id,
                "provisioner_name": provisioner_name,
                "configuration_endpoint": configuration_endpoint,
                "result": result,
            }
        )
    except StepCAError as exc:
        logger.exception("step-ca provisioner creation failed: %s", exc)
        return JSONResponse({"error": str(exc)}, status_code=502)


# ── Prepared tenant slot management ─────────────────────────────────────────


@router.delete("/tenants/prepared/{tenant_id}", name="admin_revoke_prepared")
async def revoke_prepared(
    tenant_id: str,
    request: Request,
    settings: Settings = Depends(get_settings),
):
    """Revoke all open JOIN keys for a prepared (not yet joined) tenant slot.

    Returns JSON::

        {"revoked": <count>, "tenant_id": "<id>"}
    """
    user = _get_cdm_admin(request)
    if not user:
        return JSONResponse({"error": "Unauthorized"}, status_code=403)

    all_keys = await jks.load_keys(settings)
    revoked: list[str] = []
    for key, entry in all_keys.items():
        if entry.get("tenant_id") == tenant_id and entry.get("status") == "open":
            entry["status"] = "revoked"
            all_keys[key] = entry
            revoked.append(key)

    if not revoked:
        return JSONResponse(
            {"error": f"No open JOIN key found for tenant {tenant_id!r}"},
            status_code=404,
        )

    await jks.save_keys(all_keys, settings)
    logger.info(
        "Revoked %d JOIN key(s) for tenant '%s' (by %s).",
        len(revoked),
        tenant_id,
        user.get("preferred_username", "unknown"),
    )
    return JSONResponse({"revoked": len(revoked), "tenant_id": tenant_id})
