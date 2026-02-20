"""GET /health – liveness probe."""

from fastapi import APIRouter

from app.models import HealthResponse

router = APIRouter(tags=["ops"])


@router.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    """Return service liveness status."""
    return HealthResponse()
