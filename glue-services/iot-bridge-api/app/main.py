import os

from fastapi import FastAPI
from starlette.middleware.sessions import SessionMiddleware

from app.deps import get_settings
from app.routers import enrollment, health, webhooks
from app.routers import portal, admin_portal, join

_settings = get_settings()

app = FastAPI(
    title="IoT Bridge API",
    description=(
        "Glue service that synchronises device state between "
        "step-ca (PKI), ThingsBoard, hawkBit, and WireGuard."
    ),
    version="0.1.0",
    # root_path allows FastAPI to generate correct OpenAPI URLs when served
    # behind a reverse proxy at a sub-path (e.g. nginx /api/ prefix).
    root_path=os.getenv("ROOT_PATH", ""),
)

# Session middleware is required for the tenant portal OIDC flow.
# The secret key signs the session cookie — set PORTAL_SESSION_SECRET in production.
app.add_middleware(
    SessionMiddleware,
    secret_key=_settings.portal_session_secret,
    session_cookie="cdm_portal_session",
    max_age=3600,        # 1 h
    https_only=False,    # set True in production behind TLS
    same_site="lax",
)

app.include_router(health.router)
app.include_router(enrollment.router)
app.include_router(webhooks.router)
app.include_router(portal.router)
app.include_router(admin_portal.router)
app.include_router(join.router)
