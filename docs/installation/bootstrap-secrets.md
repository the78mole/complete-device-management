# Provider-Stack: Secret & Certificate Bootstrap

This page explains how all cryptographic material — PKI keys, TLS certificates, and
service secrets — are created, distributed, and activated during the **initial start** of
the Provider-Stack.

---

## Overview

The Provider-Stack uses a strictly ordered bootstrap sequence.  Every service waits for
its prerequisites to be healthy before starting, and one-shot init containers provision
the material that long-running services consume.

!!! info "First-boot is fully automatic — `docker compose up -d` is sufficient"
    OpenBao writes the AppRole credentials for step-ca into its data volume
    (`/openbao/data/step-ca-approle.json`) during first-time init.  That volume
    is mounted read-only into the step-ca container, which reads the credentials
    automatically if no env vars are set.

    Private CA keys **never exist on disk** — all signing operations go through
    the OpenBao Transit engine.

    Override at any time via `.env`:
    ```
    OPENBAO_STEP_CA_ROLE_ID=<role-id>
    OPENBAO_STEP_CA_SECRET_ID=<secret-id>
    ```

```mermaid
sequenceDiagram
    autonumber

    actor Operator

    box "Phase 1 — Key Store (standalone, no TPM)"
        participant OB   as OpenBao<br>(Key Store)
    end
    box "Phase 2 — PKI (depends on OpenBao healthy)"
        participant SCA  as step-ca<br>(Root CA)
    end
    box "Phase 3 — Cert-Init Containers (one-shot)"
        participant RCI  as rabbitmq-cert-init
        participant MCI  as mqtt-certs-init
    end
    box "Phase 4 — Services"
        participant RMQ  as RabbitMQ
        participant SM   as system-monitor
        participant TEL  as Telegraf
        participant KC   as Keycloak
        participant IBA  as IoT Bridge API
        participant CAD  as Caddy
    end

    Note over OB,CAD: docker compose up -d

    %% ── Phase 1: OpenBao ─────────────────────────────────────────────────────
    OB->>OB: Start Raft server
    OB->>OB: bao operator init (1 key share, software-only)
    OB->>OB: bao operator unseal (auto, key from /openbao/data/.init.json)
    OB->>OB: Enable Transit engine
    OB->>OB: Create key "step-ca" (ECDSA P-256, Root CA key)
    OB->>OB: Create key "step-ca-int" (ECDSA P-256, Intermediate CA key)
    OB->>OB: Enable KV-v2 at cdm/
    OB->>OB: Enable AppRole auth<br>Create role "step-ca" (TTL: 10 years)
    OB->>OB: Write /openbao/data/.init.json<br>Write /openbao/data/step-ca-approle.json
    OB-->>Operator: Prints root token + AppRole credentials to logs (informational)

    %% ── Phase 2: step-ca ─────────────────────────────────────────────────────
    OB-->>SCA: OpenBao healthy → step-ca starts
    SCA->>SCA: Read /openbao-bootstrap/step-ca-approle.json<br>(openbao-data volume mounted read-only)
    SCA->>OB: AppRole login (role-id + secret-id)
    OB->>SCA: VAULT_TOKEN (10-year TTL)
    SCA->>OB: Read public key of transit/keys/step-ca
    SCA->>OB: transit/sign/step-ca → sign Root CA self-cert
    SCA->>OB: Read public key of transit/keys/step-ca-int
    SCA->>OB: transit/sign/step-ca → sign Intermediate CA cert
    SCA->>SCA: Write root_ca.crt + intermediate_ca.crt to disk<br>(private keys remain in OpenBao)
    SCA->>SCA: Write ca.json with kms: {type: hashivault}<br>key: hashivault:step-ca-int
    SCA->>SCA: Start CA server on :9000
    SCA-->>Operator: Prints Root CA fingerprint to logs

    Note over Operator: Set STEP_CA_FINGERPRINT in .env at your convenience<br>(needed for Tenant-Stack Sub-CA enrollment, not for Provider-Stack)

    %% ── Phase 2b: Provisioner setup (automatic, background) ─────────────────
    SCA->>SCA: Wait for CA healthy (:9000/health)
    SCA->>SCA: Run init-provisioners.sh (idempotent)<br>Add iot-bridge JWK provisioner (max-dur 8760h)<br>Add tenant-sub-ca-signer JWK provisioner<br>(skipped if they already exist)

    %% ── Phase 3a: RabbitMQ certs ─────────────────────────────────────────────
    SCA-->>RCI: step-ca healthy → start
    RCI->>SCA: CSR for rabbitmq (CN=rabbitmq, SAN=rabbitmq)
    SCA->>OB: transit/sign/step-ca-int → sign RabbitMQ TLS cert
    SCA->>RCI: Signed TLS server cert (ECDSA, exp. 8760 h)
    RCI->>RCI: Write server.crt + server.key → rabbitmq-tls volume
    RCI-->>RMQ: Exited (0) → RabbitMQ starts

    %% ── Phase 3b: MQTT client certs ──────────────────────────────────────────
    SCA-->>MCI: step-ca healthy → start
    MCI->>SCA: CSR for system-monitor (CN=system-monitor)
    SCA->>OB: transit/sign/step-ca-int → sign mTLS cert
    SCA->>MCI: Signed mTLS client cert
    MCI->>SCA: CSR for telegraf (CN=telegraf)
    SCA->>OB: transit/sign/step-ca-int → sign mTLS cert
    SCA->>MCI: Signed mTLS client cert
    MCI->>MCI: Write certs + keys → mqtt-client-tls volume
    MCI-->>SM: Exited (0) → system-monitor starts
    MCI-->>TEL: Exited (0) + rabbitmq healthy + timescaledb healthy → Telegraf starts

    %% ── Phase 4: Long-running services ──────────────────────────────────────
    RMQ->>RMQ: Load server TLS cert from rabbitmq-tls volume<br>Start MQTT broker + management UI
    SM->>SM: Load client cert from mqtt-client-tls volume<br>Connect to RabbitMQ via MQTT+mTLS
    TEL->>TEL: Load client cert from mqtt-client-tls volume<br>Collect metrics → TimescaleDB

    KC-->>IBA: Keycloak healthy → IoT Bridge API starts
    SCA-->>IBA: step-ca healthy → IoT Bridge API starts

    OB-->>CAD: OpenBao healthy → Caddy starts
    KC-->>CAD: Keycloak healthy → Caddy starts
    IBA-->>CAD: IoT Bridge API started → Caddy starts

    Note over CAD: Stack fully operational
```

---

## Key Material Created During Bootstrap

| Material | Created by | Where stored | Consumed by |
|---|---|---|---|
| Root CA key (ECDSA P-256) | `openbao` entrypoint | OpenBao Transit (`transit/keys/step-ca`) | step-ca init (signs Intermediate cert once) |
| Intermediate CA key (ECDSA P-256) | `openbao` entrypoint | OpenBao Transit (`transit/keys/step-ca-int`) | step-ca (signs ALL leaf certs at runtime) |
| Root CA cert | `step-ca` (Transit-signed) | `/home/step/certs/root_ca.crt` (step-ca volume) | TLS trust anchor, Sub-CA enrollment |
| Intermediate CA cert | `step-ca` (Transit-signed) | `/home/step/certs/intermediate_ca.crt` (step-ca volume) | TLS cert chain validation |
| RabbitMQ TLS server cert | `rabbitmq-cert-init` | `rabbitmq-tls` volume | RabbitMQ MQTT+TLS listener |
| `system-monitor` mTLS client cert | `mqtt-certs-init` | `mqtt-client-tls` volume | system-monitor publisher |
| `telegraf` mTLS client cert | `mqtt-certs-init` | `mqtt-client-tls` volume | Telegraf MQTT output |
| OpenBao root token + unseal key | `openbao` entrypoint | `/openbao/data/.init.json` | Operator (first login), auto-unseal |
| AppRole `step-ca` role-id / secret-id | `openbao` entrypoint | `/openbao/data/step-ca-approle.json` (shared volume, auto-read by step-ca) | step-ca AppRole login on every start |
| Keycloak OIDC client secrets | Keycloak (auto-generated) | Keycloak DB | Grafana, IoT Bridge API, pgAdmin, RabbitMQ |

---

## Startup Dependency Graph

```mermaid
graph TD
    OB["OpenBao ✅"]
    SCA["step-ca ✅"]
    TSDB["TimescaleDB ✅"]
    KCDB["Keycloak-DB ✅"]
    KC["Keycloak ✅"]

    RCI["rabbitmq-cert-init ⬛"]
    MCI["mqtt-certs-init ⬛"]
    RMQ["RabbitMQ ✅"]
    SM["system-monitor"]
    TEL["Telegraf"]
    IBA["IoT Bridge API"]
    GRF["Grafana"]
    PGA["pgAdmin"]
    CAD["Caddy"]

    OB --> SCA
    SCA --> RCI --> RMQ
    SCA --> MCI --> SM
    MCI --> TEL
    TSDB --> TEL
    RMQ --> TEL

    KCDB --> KC
    KC --> IBA
    SCA --> IBA
    RMQ --> IBA
    TSDB --> IBA

    KC --> GRF
    TSDB --> GRF

    TSDB --> PGA
    KC --> PGA

    OB --> CAD
    KC --> CAD
    IBA --> CAD
    GRF --> CAD

    style RCI fill:#555,color:#fff
    style MCI fill:#555,color:#fff
```

`⬛` = one-shot init container (exits after completion); `✅` = long-running service with healthcheck.

---

## Auto-Unseal on Subsequent Starts

After the first start, OpenBao **does not require manual intervention**:

1. The Raft storage already contains the initialised, sealed vault.
2. The entrypoint script reads `/openbao/data/.init.json` and calls `bao operator unseal`
   automatically with the stored key.
3. step-ca reads `/openbao-bootstrap/step-ca-approle.json` (or env var override),
   logs in via AppRole, and receives a fresh token.
4. All services that depend on `openbao: condition: service_healthy` start normally.

!!! warning "Protect the init file"
    `/openbao/data/.init.json` contains the **plaintext unseal key and root token**.
    The `openbao-data` Docker volume must be protected from unauthorised access.
    In production, use `OPENBAO_MODE=agent` and a hardened external Hub cluster instead.
    See [Key Store: Hub-and-Spoke Architecture](../security/hsm-agent-model.md).

---

## What Requires Manual Operator Steps?

| Step | When | Where documented |
|---|---|---|
| Set `STEP_CA_FINGERPRINT` in `.env` | After first `step-ca` start (fingerprint printed to logs) | [Provider Stack Setup – A4](provider-stack.md#a4----pki-provisioners-automatic) |
| Copy Keycloak OIDC client secrets to `.env` | After first Keycloak start | [Provider Stack Setup – A6](provider-stack.md#a6----retrieve-oidc-secrets) |
| Run `init-tenants.sh` | After first Keycloak start | [Provider Stack Setup – A7](provider-stack.md#a7----grant-superadmin-cross-realm-access) |

!!! success "PKI provisioners are no longer a manual step"
    `init-provisioners.sh` is called automatically by the `step-ca` entrypoint on
    every start.  The `iot-bridge` and `tenant-sub-ca-signer` provisioners are created
    on first boot and left unchanged on subsequent starts (idempotent).

All subsequent starts are **fully automatic** — no operator steps required.

!!! tip "AppRole credentials are bootstrapped automatically"
    OpenBao writes `step-ca-approle.json` into its data volume on first init.
    step-ca reads this file at startup — no manual credential copying required.
    To rotate: `bao write -f auth/approle/role/step-ca/secret-id`, then update
    `/openbao/data/step-ca-approle.json` or set `OPENBAO_STEP_CA_SECRET_ID` in `.env`.
