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
    hawkbit_url: str = "http://hawkbit:8070/hawkbit"
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

    # ── Keycloak ──────────────────────────────────────────────────────────────
    # Internal URL (container-to-container) used for token exchange
    keycloak_url: str = "http://keycloak:8080/auth"
    # Browser-facing base URL (through nginx); used to build Keycloak redirect URLs
    external_url: str = "http://localhost:8888"

    # ── Tenant Portal ─────────────────────────────────────────────────────────
    # Secret key for signing the session cookie.  MUST be changed in production.
    portal_session_secret: str = "change-this-portal-session-secret"

    # OIDC client secret for the "portal" client registered in every tenant realm.
    # Use the same value in all realms for simplicity; rotate per-realm in production.
    portal_oidc_secret: str = "changeme"

    # JSON map of tenant ID → display metadata.
    # Format: '{"<id>": {"name": "<Display Name>"}}'
    # Add new tenants here and register a matching "portal" OIDC client in their realm.
    portal_tenants_json: str = (
        '{"cdm": {"name": "CDM Platform"},'
        ' "tenant1": {"name": "Acme Devices GmbH"},'
        ' "tenant2": {"name": "Beta Industries Ltd"}}'
    )

    # ── RabbitMQ Management API ───────────────────────────────────────────────
    rabbitmq_mgmt_url: str = "http://rabbitmq:15672"
    rabbitmq_admin_user: str = "admin"
    rabbitmq_admin_password: str = "changeme"

    # ── Keycloak admin credentials (for dynamic tenant provisioning) ──────────
    keycloak_admin_user: str = "admin"
    keycloak_admin_password: str = "changeme"

    # ── step-ca Admin API (for adding OIDC provisioners per tenant) ───────────
    # Name of the bootstrap admin JWK provisioner (DOCKER_STEPCA_INIT_PROVISIONER_NAME)
    step_ca_admin_provisioner: str = "cdm-admin@cdm.local"
    # Password protecting the admin provisioner key (contents of step-ca/password.txt)
    step_ca_admin_password: str = "changeme"
    # ── step-ca sub-CA signer (for signing Tenant Sub-CA CSRs) ───────────────
    # JWK provisioner configured with x509 template isCA=true, maxPathLen=0
    step_ca_sub_ca_provisioner: str = "tenant-sub-ca-signer"
    step_ca_sub_ca_password: str = "changeme"

    # ── JOIN workflow ─────────────────────────────────────────────────────────
    # Persistent JSON store for pending/approved/rejected tenant JOIN requests.
    join_requests_db_path: str = "/data/join_requests.json"