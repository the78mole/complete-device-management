"""Application configuration loaded from environment variables."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """All settings are read from environment variables (case-insensitive)."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # ── step-ca PKI ───────────────────────────────────────────────────────────
    step_ca_url: str = "https://step-ca:9000"
    step_ca_fingerprint: str = ""
    step_ca_provisioner_name: str = "iot-bridge"
    step_ca_provisioner_password: str = "changeme"

    # ── ThingsBoard ───────────────────────────────────────────────────────────
    thingsboard_url: str = "http://thingsboard:9090"
    thingsboard_sysadmin_email: str = "sysadmin@thingsboard.org"
    thingsboard_sysadmin_password: str = "sysadmin"

    # ── hawkBit ───────────────────────────────────────────────────────────────
    hawkbit_url: str = "http://hawkbit:8070"
    hawkbit_user: str = "admin"
    hawkbit_password: str = "admin"

    # ── WireGuard ─────────────────────────────────────────────────────────────
    wireguard_config_dir: str = "/wg-config"
    wg_subnet: str = "10.13.13.0/24"
    wg_server_ip: str = "10.13.13.1"
    wg_server_url: str = "localhost"
    wg_port: int = 51820

    # ── InfluxDB (reserved for future direct writes) ──────────────────────────
    influx_url: str = "http://influxdb:8086"
    influx_token: str = ""
    influx_org: str = "cdm-org"
    influx_bucket: str = "iot-metrics"

    # ── TLS / security ────────────────────────────────────────────────────────
    # Set to False only for local evaluation when step-ca uses a self-signed cert
    # that is not yet in the container's trust store.  In production, leave True
    # and ensure STEP_CA_FINGERPRINT is set so the root cert can be pinned.
    step_ca_verify_tls: bool = True
