"""WireGuard peer-config generator and IP allocator.

Maintains a ``cdm_peers.json`` file in the WireGuard config directory to track
device-to-IP assignments across service restarts.  The linuxserver/wireguard
container stores its data at ``/config`` (mounted as ``wg-data`` volume).
"""

from __future__ import annotations

import ipaddress
import json
from pathlib import Path


class WireGuardError(Exception):
    """Raised when a WireGuard operation cannot be completed."""


class WireGuardConfig:
    """IP allocator and config generator for WireGuard peers."""

    def __init__(
        self,
        config_dir: str,
        subnet: str,
        server_ip: str,
        server_url: str = "localhost",
        server_port: int = 51820,
    ) -> None:
        self._dir = Path(config_dir)
        self._subnet = ipaddress.ip_network(subnet, strict=False)
        self._server_ip = ipaddress.ip_address(server_ip)
        self._server_url = server_url
        self._server_port = server_port
        self._peers_db = self._dir / "cdm_peers.json"

    # ── IP allocation ─────────────────────────────────────────────────────────

    def _load_peers(self) -> dict[str, str]:
        """Load the device-id → IP mapping from disk (returns {} if absent)."""
        if self._peers_db.exists():
            return json.loads(self._peers_db.read_text())  # type: ignore[no-any-return]
        return {}

    def _save_peers(self, peers: dict[str, str]) -> None:
        self._dir.mkdir(parents=True, exist_ok=True)
        self._peers_db.write_text(json.dumps(peers, indent=2))

    def allocate_ip(self, device_id: str) -> str:
        """Return the assigned IP for *device_id*, allocating a new one if needed.

        The server IP and already-assigned IPs are excluded.  Raises
        ``WireGuardError`` if the subnet is exhausted.
        """
        peers = self._load_peers()
        if device_id in peers:
            return peers[device_id]

        used = {ipaddress.ip_address(ip) for ip in peers.values()}
        used.add(self._server_ip)

        for host in self._subnet.hosts():
            if host not in used:
                peers[device_id] = str(host)
                self._save_peers(peers)
                return str(host)

        raise WireGuardError(f"No available IPs in subnet {self._subnet}")

    # ── Config generation ─────────────────────────────────────────────────────

    def get_server_pubkey(self) -> str:
        """Read the WireGuard server public key from the shared volume."""
        pubkey_file = self._dir / "server" / "publickey"
        if pubkey_file.exists():
            return pubkey_file.read_text().strip()
        return "<SERVER_PUBLIC_KEY – run: docker exec cdm-wireguard cat /config/server/publickey>"

    def write_server_peer(self, device_id: str, device_ip: str, device_pubkey: str) -> None:
        """Append a ``[Peer]`` block for the device to the server's wg0.conf."""
        wg_conf = self._dir / "wg_confs" / "wg0.conf"
        if not wg_conf.exists():
            return  # server config not yet present; skip silently
        peer_block = (
            f"\n[Peer]\n"
            f"# device: {device_id}\n"
            f"PublicKey = {device_pubkey}\n"
            f"AllowedIPs = {device_ip}/32\n"
        )
        with wg_conf.open("a") as fh:
            fh.write(peer_block)

    def generate_client_config(
        self,
        device_id: str,
        device_ip: str,
        device_pubkey: str = "",
    ) -> str:
        """Return a complete WireGuard client config (INI) for the device.

        The ``PrivateKey`` placeholder must be replaced by the device with its
        own private key before use.
        """
        if device_pubkey:
            self.write_server_peer(device_id, device_ip, device_pubkey)

        server_pubkey = self.get_server_pubkey()
        return (
            "[Interface]\n"
            f"# Device: {device_id}\n"
            f"Address = {device_ip}/24\n"
            "PrivateKey = <REPLACE_WITH_DEVICE_PRIVATE_KEY>\n"
            f"DNS = {self._server_ip}\n"
            "\n"
            "[Peer]\n"
            f"PublicKey = {server_pubkey}\n"
            f"Endpoint = {self._server_url}:{self._server_port}\n"
            f"AllowedIPs = {self._subnet}\n"
            "PersistentKeepalive = 25\n"
        )
