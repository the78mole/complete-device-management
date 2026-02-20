"""step-ca API client.

Communicates with the smallstep step-ca HTTPS API to sign X.509 CSRs using the
configured JWK provisioner (factory-enrollment flow).

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
from typing import Any

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
