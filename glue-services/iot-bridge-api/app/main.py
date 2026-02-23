import os

from fastapi import FastAPI

from app.routers import enrollment, health, webhooks

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

app.include_router(health.router)
app.include_router(enrollment.router)
app.include_router(webhooks.router)
