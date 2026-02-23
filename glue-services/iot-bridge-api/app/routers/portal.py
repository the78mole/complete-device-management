"""Tenant Portal router.

Provides a browser-facing login portal that:
  1. Asks the user for their organisation ID (no tenant list is exposed).
  2. Starts an OIDC authorisation-code flow against the matching Keycloak realm.
  3. After successful login, presents a role-based dashboard with links to
     the platform services the user is allowed to access.

Auth flow
─────────
  GET  /api/portal/            → tenant selection page
  POST /api/portal/login       → validates tenant, redirects to Keycloak
  GET  /api/portal/callback    → Keycloak callback; exchanges code, stores session
  GET  /api/portal/dashboard   → role-based dashboard (session required)
  GET  /api/portal/logout      → clears session, redirects to Keycloak logout

Role → service mapping
──────────────────────
  cdm-admin / platform-admin    : Keycloak, ThingsBoard, Grafana, hawkBit,
                                  InfluxDB, RabbitMQ, step-ca, IoT Bridge Docs
  cdm-operator / platform-op.   : ThingsBoard, Grafana, hawkBit
  cdm-viewer                    : Grafana
"""

import base64
import json
import logging
import secrets

import httpx
from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.config import Settings
from app.deps import get_settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/portal", tags=["portal"])
templates = Jinja2Templates(directory="app/templates")

# ── Role definitions ─────────────────────────────────────────────────────────

ADMIN_ROLES    = {"cdm-admin", "platform-admin"}
OPERATOR_ROLES = {"cdm-operator", "platform-operator"}
VIEWER_ROLES   = {"cdm-viewer"}


def _parse_tenants(settings: Settings) -> dict:
    try:
        return json.loads(settings.portal_tenants_json)
    except (json.JSONDecodeError, ValueError):
        logger.error("PORTAL_TENANTS_JSON is not valid JSON – using empty tenant list")
        return {}


def _callback_uri(settings: Settings) -> str:
    """Absolute redirect URI sent to Keycloak (must be browser-reachable)."""
    return f"{settings.external_url}/api/portal/callback"


def _decode_jwt_payload(token: str) -> dict:
    """Decode JWT payload without signature verification (trusted issuer assumed)."""
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)  # pad base64
        return json.loads(base64.urlsafe_b64decode(part))
    except Exception as exc:
        logger.warning("Failed to decode JWT payload: %s", exc)
        return {}


# ── Routes ───────────────────────────────────────────────────────────────────

@router.get("/", response_class=HTMLResponse, name="portal_select")
async def portal_select(request: Request):
    """Tenant selection page — no tenant list is exposed."""
    return templates.TemplateResponse(
        request, "portal/tenant_select.html", {}
    )


@router.post("/login", name="portal_login")
async def portal_login(
    request: Request,
    settings: Settings = Depends(get_settings),
):
    """Validate tenant input and start the OIDC authorisation-code flow.

    Validation: first checks the static PORTAL_TENANTS_JSON map; if not found
    there, falls back to a live Keycloak realm lookup so dynamically created
    tenants are immediately usable without a service restart.
    """
    form = await request.form()
    tenant_input = str(form.get("tenant_id", "")).strip().lower()

    tenants = _parse_tenants(settings)

    # 1. Match by exact ID or case-insensitive display name in the static map
    tenant_id: str | None = None
    for tid, meta in tenants.items():
        if tid == tenant_input or meta.get("name", "").lower() == tenant_input:
            tenant_id = tid
            break

    # 2. Fallback: live Keycloak realm existence check
    if not tenant_id:
        realm_url = f"{settings.keycloak_url}/realms/{tenant_input}"
        try:
            async with httpx.AsyncClient(verify=False, timeout=5) as client:
                resp = await client.get(realm_url)
            if resp.status_code == 200:
                tenant_id = tenant_input
        except Exception as exc:
            logger.warning("KC live realm check failed for '%s': %s", tenant_input, exc)

    if not tenant_id:
        return templates.TemplateResponse(
            request,
            "portal/tenant_select.html",
            {"error": "Organisation nicht gefunden. Bitte überprüfen Sie Ihre Eingabe."},
            status_code=400,
        )

    state = secrets.token_urlsafe(32)
    nonce = secrets.token_urlsafe(32)

    request.session["oauth_state"]  = state
    request.session["oauth_nonce"]  = nonce
    request.session["oauth_tenant"] = tenant_id

    auth_url = (
        f"{settings.keycloak_url}/realms/{tenant_id}"
        f"/protocol/openid-connect/auth"
        f"?client_id=portal"
        f"&response_type=code"
        f"&scope=openid+profile+email+roles"
        f"&redirect_uri={_callback_uri(settings)}"
        f"&state={state}"
        f"&nonce={nonce}"
    )

    # The auth_url starts with the internal keycloak URL – replace with the
    # browser-facing Keycloak URL so the browser can actually reach it.
    auth_url = auth_url.replace(
        settings.keycloak_url,
        f"{settings.external_url}/auth",
        1,
    )

    return RedirectResponse(auth_url, status_code=302)


@router.get("/callback", name="portal_callback")
async def portal_callback(
    request: Request,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
    error_description: str | None = None,
    settings: Settings = Depends(get_settings),
):
    """OAuth2 callback: exchange code → token, extract roles, store in session."""
    if error:
        msg = error_description or error
        return templates.TemplateResponse(
            request,
            "portal/tenant_select.html",
            {"error": f"Anmeldung fehlgeschlagen: {msg}"},
            status_code=400,
        )

    stored_state = request.session.get("oauth_state")
    tenant_id    = request.session.get("oauth_tenant")

    if not code or not state or state != stored_state or not tenant_id:
        return templates.TemplateResponse(
            request,
            "portal/tenant_select.html",
            {"error": "Ungültige Sitzung. Bitte erneut anmelden."},
            status_code=400,
        )

    # Exchange code for tokens (backend-to-backend via internal Keycloak URL)
    # verify=False: internal HTTP endpoint; avoids SSL_CERT_FILE env var issues
    # in Python 3.14 containers where the path may not exist.
    token_url = f"{settings.keycloak_url}/realms/{tenant_id}/protocol/openid-connect/token"

    async with httpx.AsyncClient(verify=False) as client:
        resp = await client.post(
            token_url,
            data={
                "grant_type":    "authorization_code",
                "code":          code,
                "redirect_uri":  _callback_uri(settings),
                "client_id":     "portal",
                "client_secret": settings.portal_oidc_secret,
            },
        )

    if resp.status_code != 200:
        logger.error("Token exchange failed: %s %s", resp.status_code, resp.text)
        return templates.TemplateResponse(
            request,
            "portal/tenant_select.html",
            {"error": "Token-Austausch fehlgeschlagen. Bitte erneut versuchen."},
            status_code=502,
        )

    token_data  = resp.json()
    access_token = token_data.get("access_token", "")
    id_token     = token_data.get("id_token", "")

    payload = _decode_jwt_payload(access_token)
    roles   = payload.get("realm_access", {}).get("roles", [])
    cdm_roles = [r for r in roles if r in (
        ADMIN_ROLES | OPERATOR_ROLES | VIEWER_ROLES
    )]

    tenants = _parse_tenants(settings)

    request.session["user"] = {
        "sub":                payload.get("sub", ""),
        "name":               payload.get("name") or payload.get("preferred_username", ""),
        "preferred_username": payload.get("preferred_username", ""),
        "email":              payload.get("email", ""),
        "realm":              tenant_id,
        "tenant_name":        tenants.get(tenant_id, {}).get("name", tenant_id),
        "roles":              cdm_roles,
        "id_token":           id_token,   # kept for Keycloak RP-initiated logout
    }

    # Clean up auth session data
    for key in ("oauth_state", "oauth_nonce", "oauth_tenant"):
        request.session.pop(key, None)

    return RedirectResponse("/api/portal/dashboard", status_code=302)


@router.get("/dashboard", response_class=HTMLResponse, name="portal_dashboard")
async def portal_dashboard(
    request: Request,
    settings: Settings = Depends(get_settings),
):
    """Render the role-based service dashboard."""
    user = request.session.get("user")
    if not user:
        return RedirectResponse("/api/portal/", status_code=302)

    user_roles = set(user.get("roles", []))

    # Determine highest effective role
    if user_roles & ADMIN_ROLES:
        effective_role = "admin"
    elif user_roles & OPERATOR_ROLES:
        effective_role = "operator"
    elif user_roles & VIEWER_ROLES:
        effective_role = "viewer"
    else:
        effective_role = "viewer"  # fallback: read-only

    realm = user.get("realm", "cdm")

    return templates.TemplateResponse(
        request,
        "portal/dashboard.html",
        {
            "user":             user,
            "effective_role":   effective_role,
            "realm":            realm,
            # Pass external_url so JS buildPortUrl can be initialised server-side
            "external_url":     settings.external_url,
            "keycloak_admin_url": f"{settings.external_url}/auth/admin/{realm}/console/",
        },
    )


@router.get("/logout", name="portal_logout")
async def portal_logout(
    request: Request,
    settings: Settings = Depends(get_settings),
):
    """Clear session and perform Keycloak RP-initiated logout."""
    user     = request.session.get("user", {})
    realm    = user.get("realm", "cdm")
    id_token = user.get("id_token", "")

    request.session.clear()

    post_logout_redirect = f"{settings.external_url}/api/portal/"
    logout_url = (
        f"{settings.external_url}/auth/realms/{realm}"
        f"/protocol/openid-connect/logout"
        f"?post_logout_redirect_uri={post_logout_redirect}"
        f"&client_id=portal"
    )
    if id_token:
        logout_url += f"&id_token_hint={id_token}"

    return RedirectResponse(logout_url, status_code=302)
