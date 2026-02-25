"""step-ca API client.

Communicates with the smallstep step-ca HTTPS API to sign X.509 CSRs using the
configured JWK provisioner (factory-enrollment flow).

Also provides ``StepCAAdminClient`` which uses the bootstrap admin JWK
provisioner to call the step-ca Admin API (manage provisioners at runtime).

TLS note: ``verify=False`` is intentional for local evaluation because the
step-ca root certificate is not pre-loaded into the container's trust store.
In production, pin the root CA via ``root_fingerprint`` and use
``httpx.AsyncClient(verify=<root-cert-path>)`` instead.
"""

from __future__ import annotations

import base64
import hashlib
import json
import time
from typing import Any, cast

import httpx
from cryptography import x509
from cryptography.hazmat.primitives.serialization import Encoding
from jwcrypto import jwk  # type: ignore[import]
from jwcrypto.jwe import JWE  # type: ignore[import]
from jwcrypto.jwt import JWT  # type: ignore[import]


class StepCAError(Exception):
    """Raised when the step-ca API returns an unexpected response."""


class StepCAClient:
    """Async client for the smallstep step-ca certificate-signing API."""

    def __init__(
        self,
        ca_url: str,
        provisioner_name: str,
        provisioner_password: str,
        root_fingerprint: str = "",
        verify_tls: bool = True,
    ) -> None:
        self._url = ca_url.rstrip("/")
        self._provisioner_name = provisioner_name
        self._provisioner_password = provisioner_password
        self._root_fingerprint = root_fingerprint
        self._verify_tls = verify_tls
        self._signing_key: jwk.JWK | None = None

    async def _load_signing_key(self) -> jwk.JWK:
        """Fetch and decrypt the JWK provisioner private key from step-ca."""
        if self._signing_key is not None:
            return self._signing_key

        async with httpx.AsyncClient(verify=self._verify_tls) as client:
            resp = await client.get(
                f"{self._url}/1.0/provisioners",
                timeout=10.0,
            )
            resp.raise_for_status()
            data: dict[str, Any] = resp.json()

        for prov in data.get("provisioners", []):
            if (
                prov.get("name") == self._provisioner_name
                and prov.get("type") == "JWK"
            ):
                encrypted_key_str: str = prov.get("encryptedKey", "")
                if not encrypted_key_str:
                    raise StepCAError(
                        f"Provisioner '{self._provisioner_name}' has no encryptedKey"
                    )
                # Decrypt the JWE (PBES2-HS256+A128KW) using the provisioner password
                password_key = jwk.JWK.from_password(
                    self._provisioner_password.encode("utf-8")
                )
                jwe_obj = JWE()
                jwe_obj.deserialize(encrypted_key_str, password_key)
                private_key_data: dict[str, Any] = json.loads(
                    jwe_obj.payload.decode("utf-8")
                )
                self._signing_key = jwk.JWK(**private_key_data)
                return self._signing_key

        raise StepCAError(
            f"JWK provisioner '{self._provisioner_name}' not found in step-ca"
        )

    @staticmethod
    def _csr_fingerprint(csr_pem: str) -> str:
        """SHA-256 fingerprint of the CSR DER bytes (required in the OTT claims)."""
        csr = x509.load_pem_x509_csr(csr_pem.encode())
        der = csr.public_bytes(Encoding.DER)
        return (
            base64.urlsafe_b64encode(hashlib.sha256(der).digest())
            .rstrip(b"=")
            .decode()
        )

    async def _make_ott(self, subject: str, sans: list[str], csr_pem: str) -> str:
        """Build and sign a short-lived one-time token (OTT) for /1.0/sign."""
        key = await self._load_signing_key()
        now = int(time.time())
        claims = {
            "iss": self._provisioner_name,
            "sub": subject,
            "aud": [f"{self._url}/1.0/sign"],
            "iat": now,
            "nbf": now,
            "exp": now + 300,
            "sans": sans,
            "sha": self._csr_fingerprint(csr_pem),
        }
        token = JWT(
            header={"alg": "ES256", "kid": key.key_id},
            claims=claims,
        )
        token.make_signed_token(key)
        serialized: str = token.serialize()
        return serialized

    async def sign_certificate(
        self,
        csr_pem: str,
        subject: str,
        sans: list[str],
    ) -> tuple[str, str]:
        """Submit a CSR to step-ca for signing via the JWK provisioner.

        Args:
            csr_pem: PEM-encoded PKCS#10 certificate signing request.
            subject: Common Name for the leaf certificate.
            sans:    Subject Alternative Names (typically ``[device_id]``).

        Returns:
            ``(leaf_cert_pem, ca_chain_pem)`` as PEM strings.

        Raises:
            StepCAError: on API or authentication failures.
        """
        ott = await self._make_ott(subject, sans, csr_pem)
        async with httpx.AsyncClient(verify=self._verify_tls) as client:
            resp = await client.post(
                f"{self._url}/1.0/sign",
                json={"csr": csr_pem, "ott": ott},
                timeout=30.0,
            )
            if not resp.is_success:
                raise StepCAError(
                    f"step-ca /1.0/sign returned {resp.status_code}: {resp.text}"
                )
            data: dict[str, str] = resp.json()

        return data["crt"], data["ca"]


# ─────────────────────────────────────────────────────────────────────────────
# step-ca Admin API client
# ─────────────────────────────────────────────────────────────────────────────


class StepCAAdminClient:
    """Client for the step-ca Admin API (provisioner management).

    Uses the bootstrap admin JWK provisioner to obtain an admin JWT and then
    calls ``/admin/provisioners`` to add or list OIDC provisioners.

    The admin provisioner is the JWK provisioner created during step-ca's
    initial boot (``DOCKER_STEPCA_INIT_PROVISIONER_NAME``), typically
    ``cdm-admin@cdm.local``.  Its encrypted private key is protected by the
    password in ``step-ca/password.txt``.
    """

    def __init__(
        self,
        ca_url: str,
        admin_provisioner_name: str,
        admin_password: str,
        verify_tls: bool = False,
    ) -> None:
        self._url = ca_url.rstrip("/")
        self._admin_provisioner = admin_provisioner_name
        self._admin_password = admin_password
        self._verify_tls = verify_tls
        self._admin_key: jwk.JWK | None = None

    async def _load_admin_key(self) -> Any:
        """Fetch and decrypt the admin JWK provisioner private key from step-ca."""
        if self._admin_key is not None:
            return self._admin_key

        async with httpx.AsyncClient(verify=self._verify_tls) as client:
            resp = await client.get(f"{self._url}/1.0/provisioners", timeout=10.0)
            resp.raise_for_status()
            data: dict[str, Any] = resp.json()

        for prov in data.get("provisioners", []):
            if (
                prov.get("name") == self._admin_provisioner
                and prov.get("type") == "JWK"
            ):
                encrypted_key_str: str = prov.get("encryptedKey", "")
                if not encrypted_key_str:
                    raise StepCAError(
                        f"Admin provisioner '{self._admin_provisioner}' has no encryptedKey"
                    )
                password_key = jwk.JWK.from_password(
                    self._admin_password.encode("utf-8")
                )
                jwe_obj = JWE()
                jwe_obj.deserialize(encrypted_key_str, password_key)
                private_key_data: dict[str, Any] = json.loads(
                    jwe_obj.payload.decode("utf-8")
                )
                self._admin_key = jwk.JWK(**private_key_data)
                return self._admin_key

        raise StepCAError(
            f"JWK admin provisioner '{self._admin_provisioner}' not found in step-ca"
        )

    async def _make_admin_token(self) -> str:
        """Build a short-lived JWT for the step-ca Admin API."""
        key = await self._load_admin_key()
        now = int(time.time())
        claims = {
            "iss": self._admin_provisioner,
            "sub": self._admin_provisioner,
            "aud": [f"{self._url}/admin"],
            "iat": now,
            "nbf": now,
            "exp": now + 300,
        }
        token = JWT(
            header={"alg": "ES256", "kid": key.key_id},
            claims=claims,
        )
        token.make_signed_token(key)
        return str(token.serialize())

    async def list_provisioners(self) -> list[dict]:
        """Return all provisioners registered in step-ca."""
        async with httpx.AsyncClient(verify=self._verify_tls) as client:
            resp = await client.get(f"{self._url}/1.0/provisioners", timeout=10.0)
            resp.raise_for_status()
        return cast(list[dict], resp.json().get("provisioners", []))

    async def add_oidc_provisioner(
        self,
        name: str,
        client_id: str,
        client_secret: str,
        configuration_endpoint: str,
        admin_emails: list[str] | None = None,
    ) -> dict:
        """Add an OIDC provisioner for a Keycloak tenant realm.

        Args:
            name:                   Provisioner name, e.g. ``tenant1-keycloak``.
            client_id:              OIDC client ID registered in the tenant realm.
            client_secret:          OIDC client secret.
            configuration_endpoint: Keycloak's OIDC discovery URL, e.g.
                                    ``https://.../auth/realms/tenant1/.well-known/openid-configuration``.
            admin_emails:           Optional list of email addresses that can request
                                    admin-level certificates via this provisioner.
        """
        admin_token = await self._make_admin_token()
        payload: dict[str, Any] = {
            "type": "OIDC",
            "name": name,
            "clientID": client_id,
            "clientSecret": client_secret,
            "configurationEndpoint": configuration_endpoint,
            "claims": None,
            "options": None,
        }
        if admin_emails:
            payload["admins"] = admin_emails

        async with httpx.AsyncClient(verify=self._verify_tls) as client:
            resp = await client.post(
                f"{self._url}/admin/provisioners",
                headers={"Authorization": f"Bearer {admin_token}"},
                json=payload,
                timeout=15.0,
            )
            if not resp.is_success:
                raise StepCAError(
                    f"step-ca add OIDC provisioner failed HTTP {resp.status_code}: {resp.text}"
                )
        return cast(dict, resp.json())

    async def remove_provisioner(self, name: str) -> None:
        """Remove a provisioner by name (all types)."""
        # Find the provisioner ID first
        provisioners = await self.list_provisioners()
        prov = next((p for p in provisioners if p.get("name") == name), None)
        if not prov:
            return  # already gone

        provisioner_id = prov.get("id", "")
        if not provisioner_id:
            raise StepCAError(f"Provisioner '{name}' has no ID field")

        admin_token = await self._make_admin_token()
        async with httpx.AsyncClient(verify=self._verify_tls) as client:
            resp = await client.delete(
                f"{self._url}/admin/provisioners/{provisioner_id}",
                headers={"Authorization": f"Bearer {admin_token}"},
                timeout=15.0,
            )
            if resp.status_code not in (200, 204, 404):
                raise StepCAError(
                    f"step-ca remove provisioner failed HTTP {resp.status_code}: {resp.text}"
                )

    async def sign_sub_ca_csr(
        self,
        csr_pem: str,
        tenant_id: str,
        sub_ca_provisioner_name: str,
        sub_ca_provisioner_password: str,
    ) -> tuple[str, str]:
        """Sign a Tenant Sub-CA CSR and return (signed_cert_pem, root_ca_pem).

        The provisioner identified by *sub_ca_provisioner_name* must exist in step-ca
        and have an x509 template that sets ``isCA: true, maxPathLen: 0`` so that the
        resulting certificate is a valid Intermediate CA.

        Args:
            csr_pem:                   PEM-encoded Sub-CA CSR from the Tenant-Stack.
            tenant_id:                 Tenant identifier (used as subject CN / SAN).
            sub_ca_provisioner_name:   Name of the sub-CA JWK provisioner in step-ca.
            sub_ca_provisioner_password: Password protecting that provisioner's key.

        Returns:
            ``(signed_cert_pem, root_ca_pem)``

        Raises:
            StepCAError: if the provisioner is not found or signing fails.
        """
        # ── 1. Fetch and decrypt the sub-CA provisioner JWK ──────────────────
        async with httpx.AsyncClient(verify=self._verify_tls) as client:
            resp = await client.get(f"{self._url}/1.0/provisioners", timeout=10.0)
            resp.raise_for_status()
            data: dict[str, Any] = resp.json()

        sub_ca_key: jwk.JWK | None = None
        for prov in data.get("provisioners", []):
            if prov.get("name") == sub_ca_provisioner_name and prov.get("type") == "JWK":
                encrypted_key_str: str = prov.get("encryptedKey", "")
                if not encrypted_key_str:
                    raise StepCAError(
                        f"Sub-CA provisioner '{sub_ca_provisioner_name}' has no encryptedKey"
                    )
                password_key = jwk.JWK.from_password(sub_ca_provisioner_password.encode())
                jwe_obj = JWE()
                jwe_obj.deserialize(encrypted_key_str, password_key)
                private_key_data: dict[str, Any] = json.loads(jwe_obj.payload.decode())
                sub_ca_key = jwk.JWK(**private_key_data)
                break

        if sub_ca_key is None:
            raise StepCAError(
                f"JWK provisioner '{sub_ca_provisioner_name}' not found in step-ca"
            )

        # ── 2. Compute CSR fingerprint (binds OTT to this specific CSR) ───────
        csr = x509.load_pem_x509_csr(csr_pem.encode())
        der = csr.public_bytes(Encoding.DER)
        csr_sha = (
            base64.urlsafe_b64encode(hashlib.sha256(der).digest())
            .rstrip(b"=")
            .decode()
        )

        # ── 3. Build OTT using the sub-CA provisioner key ─────────────────────
        now = int(time.time())
        claims: dict[str, Any] = {
            "iss": sub_ca_provisioner_name,
            "sub": tenant_id,
            "aud": [f"{self._url}/1.0/sign"],
            "iat": now,
            "nbf": now,
            "exp": now + 300,
            "sans": [tenant_id],
            "sha": csr_sha,
        }
        token = JWT(
            header={"alg": "ES256", "kid": sub_ca_key.key_id},
            claims=claims,
        )
        token.make_signed_token(sub_ca_key)
        ott: str = token.serialize()

        # ── 4. Submit to step-ca /1.0/sign ────────────────────────────────────
        async with httpx.AsyncClient(verify=self._verify_tls) as client:
            resp = await client.post(
                f"{self._url}/1.0/sign",
                json={"csr": csr_pem, "ott": ott},
                timeout=30.0,
            )
            if not resp.is_success:
                raise StepCAError(
                    f"step-ca sub-CA sign returned {resp.status_code}: {resp.text}"
                )
            result: dict[str, str] = resp.json()

        return result["crt"], result["ca"]

