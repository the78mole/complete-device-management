"""Unit tests for POST /devices/{device_id}/enroll."""

from __future__ import annotations

from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from app.clients.hawkbit import HawkBitClient
from app.clients.step_ca import StepCAClient, StepCAError
from tests.conftest import FAKE_CA_CHAIN_PEM, FAKE_CERT_PEM, make_test_csr

# ── Happy path ────────────────────────────────────────────────────────────────


def test_enroll_returns_200_with_all_fields(
    test_client: TestClient, csr_pem: str
) -> None:
    resp = test_client.post(
        "/devices/dev-001/enroll",
        json={
            "csr": csr_pem,
            "device_name": "Test Device 001",
            "device_type": "sensor",
            "wg_public_key": "abc123base64pubkey==",
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["certificate"] == FAKE_CERT_PEM
    assert data["ca_chain"] == FAKE_CA_CHAIN_PEM
    assert data["wireguard_ip"].startswith("10.13.13.")
    assert "[Interface]" in data["wireguard_config"]
    assert "[Peer]" in data["wireguard_config"]


def test_enroll_without_wg_public_key(
    test_client: TestClient, csr_pem: str
) -> None:
    """wg_public_key is optional; endpoint should succeed without it."""
    resp = test_client.post(
        "/devices/dev-002/enroll",
        json={"csr": csr_pem, "device_name": "Device 002"},
    )
    assert resp.status_code == 200
    assert resp.json()["wireguard_ip"].startswith("10.13.13.")


def test_enroll_allocates_sequential_ips(
    test_client: TestClient,
) -> None:
    """Different device IDs must receive different IPs."""
    csr1 = make_test_csr("device-a")
    csr2 = make_test_csr("device-b")
    r1 = test_client.post(
        "/devices/dev-a/enroll", json={"csr": csr1, "device_name": "A"}
    )
    r2 = test_client.post(
        "/devices/dev-b/enroll", json={"csr": csr2, "device_name": "B"}
    )
    assert r1.status_code == r2.status_code == 200
    assert r1.json()["wireguard_ip"] != r2.json()["wireguard_ip"]


def test_enroll_is_idempotent_for_same_device(
    test_client: TestClient, csr_pem: str
) -> None:
    """Re-enrolling the same device_id must return the same WireGuard IP."""
    r1 = test_client.post(
        "/devices/dev-repeat/enroll", json={"csr": csr_pem, "device_name": "R"}
    )
    r2 = test_client.post(
        "/devices/dev-repeat/enroll", json={"csr": csr_pem, "device_name": "R"}
    )
    assert r1.status_code == r2.status_code == 200
    assert r1.json()["wireguard_ip"] == r2.json()["wireguard_ip"]


def test_enroll_calls_hawkbit_create_target(
    test_client: TestClient, csr_pem: str, mock_hawkbit: HawkBitClient
) -> None:
    test_client.post(
        "/devices/dev-hb/enroll",
        json={"csr": csr_pem, "device_name": "HB Device"},
    )
    mock_hawkbit.create_target.assert_called_once()  # type: ignore[attr-defined]
    call_kwargs = mock_hawkbit.create_target.call_args  # type: ignore[attr-defined]
    assert call_kwargs.kwargs["controller_id"] == "dev-hb"


def test_enroll_calls_step_ca_sign(
    test_client: TestClient, csr_pem: str, mock_step_ca: StepCAClient
) -> None:
    test_client.post(
        "/devices/dev-ca/enroll",
        json={"csr": csr_pem, "device_name": "CA Device"},
    )
    mock_step_ca.sign_certificate.assert_called_once()  # type: ignore[attr-defined]
    args = mock_step_ca.sign_certificate.call_args  # type: ignore[attr-defined]
    assert args.kwargs["subject"] == "dev-ca"
    assert "dev-ca" in args.kwargs["sans"]


# ── Error handling ────────────────────────────────────────────────────────────


def test_enroll_invalid_csr_returns_422(test_client: TestClient) -> None:
    resp = test_client.post(
        "/devices/dev-bad/enroll",
        json={"csr": "NOT_A_VALID_CSR", "device_name": "Bad Device"},
    )
    assert resp.status_code == 422


def test_enroll_step_ca_error_returns_502(
    test_client: TestClient,
    csr_pem: str,
    mock_step_ca: StepCAClient,
) -> None:
    mock_step_ca.sign_certificate = AsyncMock(  # type: ignore[method-assign]
        side_effect=StepCAError("step-ca unavailable")
    )
    resp = test_client.post(
        "/devices/dev-err/enroll",
        json={"csr": csr_pem, "device_name": "Err Device"},
    )
    assert resp.status_code == 502
    assert "PKI signing failed" in resp.json()["detail"]


@pytest.mark.parametrize(
    "payload",
    [
        {},  # missing required fields
        {"csr": "ok"},  # missing device_name
        {"device_name": "x"},  # missing csr
    ],
)
def test_enroll_missing_required_fields_returns_422(
    test_client: TestClient, payload: dict
) -> None:
    resp = test_client.post("/devices/dev-x/enroll", json=payload)
    assert resp.status_code == 422
