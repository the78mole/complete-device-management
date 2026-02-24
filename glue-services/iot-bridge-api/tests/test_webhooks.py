"""Unit tests for POST /webhooks/thingsboard and /webhooks/thingsboard/telemetry."""

from __future__ import annotations

from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app.clients.hawkbit import HawkBitClient, HawkBitError
from app.clients.influxdb import InfluxDBClient, InfluxDBError

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


def _get_written_line(mock: InfluxDBClient) -> str:
    """Return the first InfluxDB line protocol string written in the last call."""
    return mock.write_lines.call_args[0][0][0]  # type: ignore[attr-defined]


def test_telemetry_writes_to_influxdb(
    test_client: TestClient, mock_influxdb: InfluxDBClient
) -> None:
    """Telemetry with numeric fields must be written to InfluxDB."""
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
    assert body["points_written"] == 1
    mock_influxdb.write_lines.assert_called_once()  # type: ignore[attr-defined]
    assert len(mock_influxdb.write_lines.call_args[0][0]) == 1  # type: ignore[attr-defined]
    line = _get_written_line(mock_influxdb)
    assert "device_telemetry" in line
    assert "tenant_id=tenant-abc" in line
    assert "device_id=dev-tel-001" in line
    assert "cpu_percent=42i" in line


def test_telemetry_includes_string_fields(
    test_client: TestClient, mock_influxdb: InfluxDBClient
) -> None:
    """String fields (e.g. ota_status) must be quoted in line protocol."""
    resp = test_client.post(
        "/webhooks/thingsboard/telemetry",
        json={
            "msgType": "POST_TELEMETRY_REQUEST",
            "metadata": {"deviceId": "dev-str-001", "tenantId": "t1"},
            "data": {"ota_status": "idle", "cpu_percent": 10},
        },
    )
    assert resp.status_code == 200
    line = _get_written_line(mock_influxdb)
    assert 'ota_status="idle"' in line


def test_telemetry_escapes_special_chars_in_strings(
    test_client: TestClient, mock_influxdb: InfluxDBClient
) -> None:
    """Backslashes and double-quotes in string fields must be properly escaped."""
    resp = test_client.post(
        "/webhooks/thingsboard/telemetry",
        json={
            "msgType": "POST_TELEMETRY_REQUEST",
            "metadata": {"deviceId": "dev-esc-001", "tenantId": "t1"},
            "data": {"msg": 'say "hello" \\world'},
        },
    )
    assert resp.status_code == 200
    line = _get_written_line(mock_influxdb)
    # Backslash and double-quote must be escaped in InfluxDB line protocol
    assert r'say \"hello\" \\world' in line


def test_telemetry_ignores_empty_data(
    test_client: TestClient, mock_influxdb: InfluxDBClient
) -> None:
    """Telemetry with no numeric/string fields must be silently ignored."""
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
    mock_influxdb.write_lines.assert_not_called()  # type: ignore[attr-defined]


def test_telemetry_ignores_event_without_device_id(
    test_client: TestClient, mock_influxdb: InfluxDBClient
) -> None:
    """Events with no identifiable device ID are acknowledged but not written."""
    resp = test_client.post(
        "/webhooks/thingsboard/telemetry",
        json={"msgType": "POST_TELEMETRY_REQUEST", "metadata": {}, "data": {"v": 1}},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "ignored"
    mock_influxdb.write_lines.assert_not_called()  # type: ignore[attr-defined]


def test_telemetry_influxdb_error_returns_503(
    test_client: TestClient, mock_influxdb: InfluxDBClient
) -> None:
    """InfluxDB write failures must result in a 503 response."""
    mock_influxdb.write_lines = AsyncMock(  # type: ignore[method-assign]
        side_effect=InfluxDBError("connection refused")
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
    assert "InfluxDB write failed" in resp.json()["detail"]


def test_telemetry_tenant_isolation_tags(
    test_client: TestClient, mock_influxdb: InfluxDBClient
) -> None:
    """Two devices from different tenants produce lines with distinct tenant tags."""
    for tenant, device in [("tenant-A", "dev-A"), ("tenant-B", "dev-B")]:
        mock_influxdb.write_lines.reset_mock()  # type: ignore[attr-defined]
        resp = test_client.post(
            "/webhooks/thingsboard/telemetry",
            json={
                "msgType": "POST_TELEMETRY_REQUEST",
                "metadata": {"deviceId": device, "tenantId": tenant},
                "data": {"cpu_percent": 20},
            },
        )
        assert resp.status_code == 200
        line = _get_written_line(mock_influxdb)
        assert f"tenant_id={tenant}" in line
        assert f"device_id={device}" in line
