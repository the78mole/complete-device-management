"""POST /devices/{device_id}/enroll – factory / simulated device enrollment.

Flow
----
1.  Validate the incoming PKCS#10 CSR (reject malformed requests early).
2.  Forward the CSR to step-ca for signing via the JWK provisioner OTT flow.
3.  Create the corresponding target in hawkBit (idempotent – skip if exists).
4.  Allocate a WireGuard VPN IP and generate the client-side peer config.
5.  Return the signed certificate, CA chain, VPN IP and WireGuard config.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.clients.hawkbit import HawkBitClient, HawkBitError
from app.clients.step_ca import StepCAClient, StepCAError
from app.clients.wireguard import WireGuardConfig
from app.deps import get_hawkbit_client, get_step_ca_client, get_wg_config
from app.models import EnrollmentRequest, EnrollmentResponse

router = APIRouter(prefix="/devices", tags=["enrollment"])


def _validate_csr(csr_pem: str) -> None:
    """Parse the CSR PEM and raise HTTP 422 if it is malformed."""
    from cryptography import x509
    from cryptography.exceptions import InvalidSignature

    try:
        csr = x509.load_pem_x509_csr(csr_pem.encode())
        if not csr.is_signature_valid:
            raise ValueError("CSR signature is invalid")
    except (InvalidSignature, ValueError, Exception) as exc:
        raise HTTPException(status_code=422, detail=f"Invalid CSR: {exc}") from exc


@router.post(
    "/{device_id}/enroll",
    response_model=EnrollmentResponse,
    summary="Enroll a device (factory/simulation)",
    description=(
        "Accepts a PKCS#10 CSR, signs it via step-ca, "
        "creates a hawkBit target, and allocates a WireGuard VPN IP."
    ),
)
async def enroll_device(
    device_id: str,
    body: EnrollmentRequest,
    step_ca: StepCAClient = Depends(get_step_ca_client),
    hawkbit: HawkBitClient = Depends(get_hawkbit_client),
    wg: WireGuardConfig = Depends(get_wg_config),
) -> EnrollmentResponse:
    """Enroll a new device into the platform."""
    # ── 1. Validate CSR ──────────────────────────────────────────────────────
    _validate_csr(body.csr)

    # ── 2. Sign via step-ca ──────────────────────────────────────────────────
    try:
        cert_pem, ca_chain_pem = await step_ca.sign_certificate(
            csr_pem=body.csr,
            subject=device_id,
            sans=[device_id],
        )
    except StepCAError as exc:
        raise HTTPException(
            status_code=502, detail=f"PKI signing failed: {exc}"
        ) from exc

    # ── 3. Create / ensure hawkBit target ────────────────────────────────────
    try:
        existing = await hawkbit.get_target(device_id)
        if not existing:
            await hawkbit.create_target(
                controller_id=device_id,
                name=body.device_name,
                attributes={"device_type": body.device_type},
            )
    except HawkBitError as exc:
        raise HTTPException(
            status_code=502, detail=f"hawkBit provisioning failed: {exc}"
        ) from exc

    # ── 4. WireGuard IP + config ─────────────────────────────────────────────
    wg_ip = wg.allocate_ip(device_id)
    wg_cfg = wg.generate_client_config(
        device_id=device_id,
        device_ip=wg_ip,
        device_pubkey=body.wg_public_key or "",
    )

    return EnrollmentResponse(
        certificate=cert_pem,
        ca_chain=ca_chain_pem,
        wireguard_ip=wg_ip,
        wireguard_config=wg_cfg,
    )
