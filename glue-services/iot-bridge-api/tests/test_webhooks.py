"""Unit tests for POST /webhooks/thingsboard."""

from __future__ import annotations

from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app.clients.hawkbit import HawkBitClient, HawkBitError

# ── Happy path ────────────────────────────────────────────────────────────────


def test_webhook_provisions_new_device(
    test_client: TestClient, mock_hawkbit: HawkBitClient
) -> None:
    """A first-connect event for an unknown device creates a hawkBit target."""
    resp = test_client.post(
        "/webhooks/thingsboard",
        json={
            "msgType": "POST_CONNECT_REQUEST",
            "metadata": {
                "deviceId": "dev-wb-001",
                "deviceName": "Webhook Device 001",
                "deviceType": "sensor",
            },
            "data": {},
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "provisioned"
    assert body["device_id"] == "dev-wb-001"
    assert body["wireguard_ip"].startswith("10.13.13.")
    mock_hawkbit.create_target.assert_called_once()  # type: ignore[attr-defined]


def test_webhook_skips_already_provisioned_device(
    test_client: TestClient, mock_hawkbit: HawkBitClient
) -> None:
    """A second event for the same device must NOT create a duplicate target."""
    mock_hawkbit.get_target = AsyncMock(  # type: ignore[method-assign]
        return_value={"controllerId": "dev-existing", "name": "Existing Device"}
    )
    resp = test_client.post(
        "/webhooks/thingsboard",
        json={
            "msgType": "POST_CONNECT_REQUEST",
            "metadata": {"deviceId": "dev-existing", "deviceName": "Existing Device"},
            "data": {},
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "already_provisioned"
    assert body["device_id"] == "dev-existing"
    mock_hawkbit.create_target.assert_not_called()  # type: ignore[attr-defined]


def test_webhook_assigns_consistent_ip_on_repeat(
    test_client: TestClient,
) -> None:
    """Sending the same event twice must return the same WireGuard IP."""
    payload = {
        "msgType": "POST_CONNECT_REQUEST",
        "metadata": {"deviceId": "dev-repeat-wb", "deviceName": "Repeat"},
        "data": {},
    }
    r1 = test_client.post("/webhooks/thingsboard", json=payload)
    r2 = test_client.post("/webhooks/thingsboard", json=payload)
    assert r1.status_code == r2.status_code == 200
    assert r1.json()["wireguard_ip"] == r2.json()["wireguard_ip"]


def test_webhook_uses_clientid_when_deviceid_absent(
    test_client: TestClient,
) -> None:
    """Falls back to ``clientId`` if ``deviceId`` is missing in metadata."""
    resp = test_client.post(
        "/webhooks/thingsboard",
        json={
            "msgType": "POST_CONNECT_REQUEST",
            "metadata": {"clientId": "fallback-device", "deviceName": "Fallback"},
            "data": {},
        },
    )
    assert resp.status_code == 200
    assert resp.json()["device_id"] == "fallback-device"


# ── Edge cases ────────────────────────────────────────────────────────────────


def test_webhook_ignores_event_without_device_id(
    test_client: TestClient,
) -> None:
    """Events with no identifiable device should be acknowledged but ignored."""
    resp = test_client.post(
        "/webhooks/thingsboard",
        json={"msgType": "UNKNOWN", "metadata": {}, "data": {}},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "ignored"


def test_webhook_hawkbit_error_returns_502(
    test_client: TestClient, mock_hawkbit: HawkBitClient
) -> None:
    mock_hawkbit.get_target = AsyncMock(  # type: ignore[method-assign]
        side_effect=HawkBitError("connection refused")
    )
    resp = test_client.post(
        "/webhooks/thingsboard",
        json={
            "msgType": "POST_CONNECT_REQUEST",
            "metadata": {"deviceId": "dev-502"},
            "data": {},
        },
    )
    assert resp.status_code == 502
    assert "hawkBit query failed" in resp.json()["detail"]


@pytest.mark.parametrize(
    "metadata,expected_id",
    [
        ({"deviceId": "d1", "deviceName": "n"}, "d1"),
        ({"clientId": "d2", "deviceName": "n"}, "d2"),
        ({"deviceName": "d3"}, "d3"),
    ],
)
def test_webhook_device_id_extraction(
    test_client: TestClient, metadata: dict, expected_id: str
) -> None:
    """Verify the priority order for device ID extraction from metadata."""
    resp = test_client.post(
        "/webhooks/thingsboard",
        json={"msgType": "POST_CONNECT_REQUEST", "metadata": metadata, "data": {}},
    )
    assert resp.status_code == 200
    assert resp.json()["device_id"] == expected_id
