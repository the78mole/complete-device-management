"""Shared pytest fixtures and helpers.

External clients (step-ca, hawkBit) are replaced by lightweight mocks via
FastAPI's ``dependency_overrides`` mechanism so tests run without any live
services.  WireGuard uses ``tmp_path`` for file-system isolation.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID
from fastapi.testclient import TestClient

from app.clients.hawkbit import HawkBitClient
from app.clients.step_ca import StepCAClient
from app.clients.wireguard import WireGuardConfig
from app.deps import get_hawkbit_client, get_step_ca_client, get_wg_config
from app.main import app

# ── Constants ─────────────────────────────────────────────────────────────────

FAKE_CERT_PEM = (
    "-----BEGIN CERTIFICATE-----\n"
    "MIIBFAKE0000000000000000000000000000000000000000000000000000\n"
    "-----END CERTIFICATE-----\n"
)
FAKE_CA_CHAIN_PEM = (
    "-----BEGIN CERTIFICATE-----\n"
    "MIIBFAKECA000000000000000000000000000000000000000000000000000\n"
    "-----END CERTIFICATE-----\n"
)

# ── CSR helper ────────────────────────────────────────────────────────────────


def make_test_csr(cn: str = "device-test-001") -> str:
    """Generate a valid PKCS#10 CSR for use in tests."""
    key = ec.generate_private_key(ec.SECP256R1())
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(
            x509.Name(
                [
                    x509.NameAttribute(NameOID.COMMON_NAME, cn),
                    x509.NameAttribute(NameOID.ORGANIZATION_NAME, "CDM IoT Platform"),
                ]
            )
        )
        .sign(key, hashes.SHA256())
    )
    return csr.public_bytes(serialization.Encoding.PEM).decode()


# ── Fixtures ──────────────────────────────────────────────────────────────────


@pytest.fixture()
def csr_pem() -> str:
    return make_test_csr()


@pytest.fixture()
def mock_step_ca() -> StepCAClient:
    client: StepCAClient = MagicMock(spec=StepCAClient)
    client.sign_certificate = AsyncMock(  # type: ignore[method-assign]
        return_value=(FAKE_CERT_PEM, FAKE_CA_CHAIN_PEM)
    )
    return client


@pytest.fixture()
def mock_hawkbit() -> HawkBitClient:
    client: HawkBitClient = MagicMock(spec=HawkBitClient)
    client.get_target = AsyncMock(return_value=None)  # type: ignore[method-assign]
    client.create_target = AsyncMock(  # type: ignore[method-assign]
        return_value={"controllerId": "device-test-001", "name": "Test Device 001"}
    )
    return client


@pytest.fixture()
def mock_wg_config(tmp_path: Path) -> WireGuardConfig:
    return WireGuardConfig(
        config_dir=str(tmp_path),
        subnet="10.13.13.0/24",
        server_ip="10.13.13.1",
        server_url="localhost",
        server_port=51820,
    )


@pytest.fixture()
def test_client(
    mock_step_ca: StepCAClient,
    mock_hawkbit: HawkBitClient,
    mock_wg_config: WireGuardConfig,
) -> TestClient:
    app.dependency_overrides[get_step_ca_client] = lambda: mock_step_ca
    app.dependency_overrides[get_hawkbit_client] = lambda: mock_hawkbit
    app.dependency_overrides[get_wg_config] = lambda: mock_wg_config
    yield TestClient(app)  # type: ignore[misc]
    app.dependency_overrides.clear()
