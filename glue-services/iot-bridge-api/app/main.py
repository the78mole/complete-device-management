"""FastAPI application entry point."""

from fastapi import FastAPI

from app.routers import enrollment, health, webhooks

app = FastAPI(
    title="IoT Bridge API",
    description=(
        "Glue service that synchronises device state between "
        "step-ca (PKI), ThingsBoard, hawkBit, and WireGuard."
    ),
    version="0.1.0",
)

app.include_router(health.router)
app.include_router(enrollment.router)
app.include_router(webhooks.router)
