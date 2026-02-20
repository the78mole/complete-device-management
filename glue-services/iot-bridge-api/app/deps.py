"""FastAPI dependency providers.

All client singletons are created here and injected via ``Depends``.
Tests override these functions via ``app.dependency_overrides``.
"""

from functools import lru_cache

from fastapi import Depends

from app.clients.hawkbit import HawkBitClient
from app.clients.step_ca import StepCAClient
from app.clients.wireguard import WireGuardConfig
from app.config import Settings


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


def get_step_ca_client(settings: Settings = Depends(get_settings)) -> StepCAClient:
    return StepCAClient(
        ca_url=settings.step_ca_url,
        provisioner_name=settings.step_ca_provisioner_name,
        provisioner_password=settings.step_ca_provisioner_password,
        root_fingerprint=settings.step_ca_fingerprint,
        verify_tls=settings.step_ca_verify_tls,
    )


def get_hawkbit_client(settings: Settings = Depends(get_settings)) -> HawkBitClient:
    return HawkBitClient(
        base_url=settings.hawkbit_url,
        username=settings.hawkbit_user,
        password=settings.hawkbit_password,
    )


def get_wg_config(settings: Settings = Depends(get_settings)) -> WireGuardConfig:
    return WireGuardConfig(
        config_dir=settings.wireguard_config_dir,
        subnet=settings.wg_subnet,
        server_ip=settings.wg_server_ip,
        server_url=settings.wg_server_url,
        server_port=settings.wg_port,
    )
