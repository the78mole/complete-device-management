import os

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi
from starlette.middleware.sessions import SessionMiddleware

from app.deps import get_settings
from app.routers import admin_portal, enrollment, health, join, portal, webhooks

_settings = get_settings()

# Keycloak base URL as seen from the **browser** (external URL).
# The Swagger UI OAuth2 flow runs in the browser, so we must use the public URL.
_kc_ext = _settings.external_url.rstrip("/") + "/auth/realms/cdm/protocol/openid-connect"

app = FastAPI(
    title="IoT Bridge API",
    description=(
        "Glue service that synchronises device state between "
        "step-ca (PKI), ThingsBoard, hawkBit, and WireGuard.\n\n"
        "**Authentication** – admin endpoints require a Keycloak `cdm` realm token "
        "with the `cdm-admin` or `platform-admin` role.\n"
        "Click **Authorize** and log in with your admin account to test them here."
    ),
    version="0.1.0",
    # root_path allows FastAPI to generate correct OpenAPI URLs when served
    # behind a reverse proxy at a sub-path (e.g. nginx /api/ prefix).
    root_path=os.getenv("ROOT_PATH", ""),
    # Pre-populate the Swagger UI Authorize dialog with the Keycloak client.
    swagger_ui_init_oauth={
        "clientId": "dashboard",
        "scopes": "openid",
        "usePkceWithAuthorizationCodeGrant": True,
    },
)

# Session middleware is required for the tenant portal OIDC flow.
# The secret key signs the session cookie — set PORTAL_SESSION_SECRET in production.
app.add_middleware(
    SessionMiddleware,
    secret_key=_settings.portal_session_secret,
    session_cookie="cdm_portal_session",
    max_age=3600,  # 1 h
    https_only=False,  # set True in production behind TLS
    same_site="lax",
)

app.include_router(health.router)
app.include_router(enrollment.router)
app.include_router(webhooks.router)
app.include_router(portal.router)
app.include_router(admin_portal.router)
app.include_router(join.router)


# ── Custom OpenAPI schema: inject Keycloak OAuth2 + Bearer security schemes ──


def _custom_openapi() -> dict:
    if app.openapi_schema:
        return app.openapi_schema  # type: ignore[return-value]

    schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )

    # Security schemes
    schema.setdefault("components", {}).setdefault("securitySchemes", {})
    schemes = schema["components"]["securitySchemes"]

    # 1. Plain Bearer – paste a token obtained externally (e.g. from the portal)
    schemes["BearerAuth"] = {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT",
        "description": (
            "Paste a Keycloak access token (cdm realm, cdm-admin or platform-admin role). "
            "You can copy it from the browser dev-tools while logged into the portal."
        ),
    }

    # 2. OAuth2 Authorization Code + PKCE via Keycloak (runs entirely in the browser)
    schemes["KeycloakOAuth2"] = {
        "type": "oauth2",
        "flows": {
            "authorizationCode": {
                "authorizationUrl": f"{_kc_ext}/auth",
                "tokenUrl": f"{_kc_ext}/token",
                "scopes": {"openid": "OpenID Connect identity token"},
            }
        },
    }

    # Apply both schemes globally so every endpoint shows the lock icon.
    # Endpoints that don't need auth simply ignore the header.
    schema["security"] = [{"BearerAuth": []}, {"KeycloakOAuth2": ["openid"]}]

    app.openapi_schema = schema
    return schema  # type: ignore[return-value]


app.openapi = _custom_openapi  # type: ignore[method-assign]
