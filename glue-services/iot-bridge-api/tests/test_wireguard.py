"""Unit tests for WireGuardConfig – pure logic, no mocks needed."""

from __future__ import annotations

import ipaddress
import json
from pathlib import Path

import pytest

from app.clients.wireguard import WireGuardConfig, WireGuardError

# ── Fixtures ──────────────────────────────────────────────────────────────────


@pytest.fixture()
def wg(tmp_path: Path) -> WireGuardConfig:
    return WireGuardConfig(
        config_dir=str(tmp_path),
        subnet="10.13.13.0/24",
        server_ip="10.13.13.1",
        server_url="vpn.example.com",
        server_port=51820,
    )


# ── IP allocation ─────────────────────────────────────────────────────────────


def test_first_allocated_ip_skips_server_ip(wg: WireGuardConfig) -> None:
    ip = wg.allocate_ip("device-001")
    assert ip != "10.13.13.1"  # server IP must never be assigned to a device
    assert ipaddress.ip_address(ip) in ipaddress.ip_network("10.13.13.0/24")


def test_first_ip_is_10_13_13_2(wg: WireGuardConfig) -> None:
    """With server at .1, first allocation should be .2."""
    assert wg.allocate_ip("device-001") == "10.13.13.2"


def test_second_device_gets_incremented_ip(wg: WireGuardConfig) -> None:
    wg.allocate_ip("device-001")
    assert wg.allocate_ip("device-002") == "10.13.13.3"


def test_same_device_returns_same_ip(wg: WireGuardConfig) -> None:
    ip1 = wg.allocate_ip("device-x")
    ip2 = wg.allocate_ip("device-x")
    assert ip1 == ip2


def test_allocations_persisted_across_instances(
    tmp_path: Path,
) -> None:
    """A new WireGuardConfig instance reading the same dir returns the same IPs."""
    wg1 = WireGuardConfig(str(tmp_path), "10.13.13.0/24", "10.13.13.1")
    ip = wg1.allocate_ip("device-persist")

    wg2 = WireGuardConfig(str(tmp_path), "10.13.13.0/24", "10.13.13.1")
    assert wg2.allocate_ip("device-persist") == ip


def test_peers_json_written_correctly(
    wg: WireGuardConfig, tmp_path: Path
) -> None:
    wg.allocate_ip("dev-a")
    wg.allocate_ip("dev-b")
    peers_file = tmp_path / "cdm_peers.json"
    assert peers_file.exists()
    peers = json.loads(peers_file.read_text())
    assert "dev-a" in peers
    assert "dev-b" in peers
    assert peers["dev-a"] != peers["dev-b"]


def test_subnet_exhaustion_raises(tmp_path: Path) -> None:
    """A /30 subnet has 2 usable hosts; after both are taken the next should raise."""
    wg_small = WireGuardConfig(str(tmp_path), "10.0.0.0/30", "10.0.0.1")
    wg_small.allocate_ip("device-a")  # 10.0.0.2
    with pytest.raises(WireGuardError, match="No available IPs"):
        wg_small.allocate_ip("device-b")  # 10.0.0.3 doesn't exist in /30


# ── Client config generation ──────────────────────────────────────────────────


def test_generate_client_config_contains_required_sections(
    wg: WireGuardConfig,
) -> None:
    ip = wg.allocate_ip("dev-cfg")
    cfg = wg.generate_client_config("dev-cfg", ip)
    assert "[Interface]" in cfg
    assert "[Peer]" in cfg
    assert ip in cfg
    assert "PersistentKeepalive" in cfg


def test_generate_client_config_includes_server_url(
    wg: WireGuardConfig,
) -> None:
    ip = wg.allocate_ip("dev-url")
    cfg = wg.generate_client_config("dev-url", ip)
    # Verify the Endpoint line is correctly formatted (exact substring check)
    assert "Endpoint = vpn.example.com:51820" in cfg


def test_generate_client_config_no_wg0_conf_does_not_crash(
    wg: WireGuardConfig,
) -> None:
    """write_server_peer must not raise when wg0.conf is absent."""
    ip = wg.allocate_ip("dev-noconf")
    cfg = wg.generate_client_config("dev-noconf", ip, device_pubkey="fakepubkey==")
    assert "[Interface]" in cfg  # config returned even without server-side file
