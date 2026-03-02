"""Unit tests for POST /webhooks/thingsboard and /webhooks/thingsboard/telemetry."""

from __future__ import annotations

from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app.clients.hawkbit import HawkBitClient, HawkBitError
from app.clients.timescaledb import TimescaleDBClient, TimescaleDBError

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


# ── Telemetry webhook tests ───────────────────────────────────────────────────


def _get_written_rows(mock: TimescaleDBClient) -> list[dict]:
    """Return the rows list passed to write_metrics in the last call."""
    return mock.write_metrics.call_args[0][0]  # type: ignore[attr-defined]


def test_telemetry_writes_to_timescaledb(
    test_client: TestClient, mock_timescaledb: TimescaleDBClient
) -> None:
    """Telemetry with numeric fields must be written to TimescaleDB."""
    resp = test_client.post(
        "/webhooks/thingsboard/telemetry",
        json={
            "msgType": "POST_TELEMETRY_REQUEST",
            "metadata": {
                "deviceId": "dev-tel-001",
                "deviceName": "Telemetry Device 001",
                "tenantId": "tenant-abc",
            },
            "data": {"cpu_percent": 42, "ram_percent": 68, "temperature_c": 55},
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "written"
    assert body["device_id"] == "dev-tel-001"
    assert body["tenant_id"] == "tenant-abc"
    assert body["points_written"] == 3  # one row per metric
    mock_timescaledb.write_metrics.assert_called_once()  # type: ignore[attr-defined]
    rows = _get_written_rows(mock_timescaledb)
    assert len(rows) == 3
    metric_names = {r["metric_name"] for r in rows}
    assert metric_names == {"cpu_percent", "ram_percent", "temperature_c"}
    cpu_row = next(r for r in rows if r["metric_name"] == "cpu_percent")
    assert cpu_row["value"] == 42.0
    assert cpu_row["tenant_id"] == "tenant-abc"
    assert cpu_row["device_id"] == "dev-tel-001"


def test_telemetry_stores_string_fields_with_null_value(
    test_client: TestClient, mock_timescaledb: TimescaleDBClient
) -> None:
    """String fields (e.g. ota_status) must be stored with value=None and raw_type tag."""
    resp = test_client.post(
        "/webhooks/thingsboard/telemetry",
        json={
            "msgType": "POST_TELEMETRY_REQUEST",
            "metadata": {"deviceId": "dev-str-001", "tenantId": "t1"},
            "data": {"ota_status": "idle", "cpu_percent": 10},
        },
    )
    assert resp.status_code == 200
    rows = _get_written_rows(mock_timescaledb)
    str_row = next(r for r in rows if r["metric_name"] == "ota_status")
    assert str_row["value"] is None
    assert str_row["tags"]["raw_type"] == "str"
    num_row = next(r for r in rows if r["metric_name"] == "cpu_percent")
    assert num_row["value"] == 10.0


def test_telemetry_row_contains_tenant_and_device(
    test_client: TestClient, mock_timescaledb: TimescaleDBClient
) -> None:
    """Every row must carry tenant_id and device_id for multi-tenant isolation."""
    resp = test_client.post(
        "/webhooks/thingsboard/telemetry",
        json={
            "msgType": "POST_TELEMETRY_REQUEST",
            "metadata": {"deviceId": "dev-iso-001", "tenantId": "t-iso"},
            "data": {"temp": 22.5},
        },
    )
    assert resp.status_code == 200
    rows = _get_written_rows(mock_timescaledb)
    assert all(r["tenant_id"] == "t-iso" for r in rows)
    assert all(r["device_id"] == "dev-iso-001" for r in rows)


def test_telemetry_ignores_empty_data(
    test_client: TestClient, mock_timescaledb: TimescaleDBClient
) -> None:
    """Telemetry with no fields must be silently ignored without a DB write."""
    resp = test_client.post(
        "/webhooks/thingsboard/telemetry",
        json={
            "msgType": "POST_TELEMETRY_REQUEST",
            "metadata": {"deviceId": "dev-empty", "tenantId": "t1"},
            "data": {},
        },
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "ignored"
    mock_timescaledb.write_metrics.assert_not_called()  # type: ignore[attr-defined]


def test_telemetry_ignores_event_without_device_id(
    test_client: TestClient, mock_timescaledb: TimescaleDBClient
) -> None:
    """Events with no identifiable device ID are acknowledged but not written."""
    resp = test_client.post(
        "/webhooks/thingsboard/telemetry",
        json={"msgType": "POST_TELEMETRY_REQUEST", "metadata": {}, "data": {"v": 1}},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "ignored"
    mock_timescaledb.write_metrics.assert_not_called()  # type: ignore[attr-defined]


def test_telemetry_timescaledb_error_returns_503(
    test_client: TestClient, mock_timescaledb: TimescaleDBClient
) -> None:
    """TimescaleDB write failures must result in a 503 response."""
    mock_timescaledb.write_metrics = AsyncMock(  # type: ignore[method-assign]
        side_effect=TimescaleDBError("connection refused")
    )
    resp = test_client.post(
        "/webhooks/thingsboard/telemetry",
        json={
            "msgType": "POST_TELEMETRY_REQUEST",
            "metadata": {"deviceId": "dev-503", "tenantId": "t1"},
            "data": {"cpu_percent": 50},
        },
    )
    assert resp.status_code == 503
    assert "TimescaleDB write failed" in resp.json()["detail"]


def test_telemetry_tenant_isolation_separate_calls(
    test_client: TestClient, mock_timescaledb: TimescaleDBClient
) -> None:
    """Two devices from different tenants produce rows with distinct tenant_id values."""
    for tenant, device in [("tenant-A", "dev-A"), ("tenant-B", "dev-B")]:
        mock_timescaledb.write_metrics.reset_mock()  # type: ignore[attr-defined]
        resp = test_client.post(
            "/webhooks/thingsboard/telemetry",
            json={
                "msgType": "POST_TELEMETRY_REQUEST",
                "metadata": {"deviceId": device, "tenantId": tenant},
                "data": {"cpu_percent": 20},
            },
        )
        assert resp.status_code == 200
        rows = _get_written_rows(mock_timescaledb)
        assert all(r["tenant_id"] == tenant for r in rows)
        assert all(r["device_id"] == device for r in rows)
