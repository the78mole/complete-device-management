# Access Matrix — Keycloak Users & Endpoint Permissions

This page documents which Keycloak users and roles have access to which provider-stack
endpoints, and at what permission level.

!!! tip "Keep this page up to date"
    The [Role-Based Access Matrix](#role-based-access-matrix) is derived from the realm
    templates and does not change unless you edit `realm-cdm.json.tpl` or
    `realm-provider.json.tpl`.  
    The [Current User Assignments](#current-user-assignments) section shows users as they
    exist in a running deployment and can be regenerated at any time:

    ```bash
    cd provider-stack
    python3 keycloak/generate-access-matrix.py | tee ../docs/architecture/access-matrix-snapshot.md
    ```

---

## Provider-Stack Endpoints

| Path / Port | Service | Auth realm | OIDC Client |
|---|---|---|---|
| `/` | Landing page | — (public) | — |
| `/auth/admin/cdm/console/` | Keycloak CDM Admin | `master` or `cdm` realm-admin | admin-cli / realm-management |
| `/auth/admin/provider/console/` | Keycloak Provider Admin | `master` or `provider` realm-admin | admin-cli / realm-management |
| `/auth/realms/cdm/account/` | CDM Account Portal | `cdm` | account-console |
| `/auth/realms/provider/account/` | Provider Account Portal | `provider` | account-console |
| `/grafana/` | Grafana (platform dashboards) | `cdm` | `grafana` |
| `/api/` | IoT Bridge API | `cdm` (JWT Bearer) | `iot-bridge` |
| `/api/portal/` | Tenant Portal | `cdm` | `portal` |
| `/pgadmin/` | pgAdmin (TimescaleDB admin) | `cdm` | `pgadmin` |
| `/rabbitmq/` | RabbitMQ Management | `provider` | `rabbitmq-management` |
| `/pki/` | step-ca (PKI) | — (provisioner password) | — |

---

## Role-Based Access Matrix

Derived from the realm templates.  The mapping is authoritative and does not depend on
the current runtime state of Keycloak.

### Legend

| Symbol | Meaning |
|---|---|
| ✅ | Full / Admin access |
| 🔵 | Editor / Write access |
| 👁 | Read-only / Viewer access |
| ⚠️ | Access granted but **should be restricted** — see security note |
| ✗ | No access |
| — | Not applicable / cert-based |

### `cdm` realm roles

| Role | Grafana | IoT Bridge API | Tenant Portal | pgAdmin | RabbitMQ | KC CDM Admin | KC Provider Admin |
|---|---|---|---|---|---|---|---|
| `cdm-admin` | ✅ Admin | ✅ Full | ✅ Admin view | ⚠️ DB Superuser[^1] | ✗ | ✗[^2] | ✗ |
| `cdm-operator` | 🔵 Editor | 🔵 Read + deploy | 🔵 Operator view | ⚠️ DB Superuser[^1] | ✗ | ✗ | ✗ |
| `cdm-viewer` | 👁 Viewer | 👁 Read-only | 👁 Viewer view | ⚠️ DB Superuser[^1] | ✗ | ✗ | ✗ |

### `provider` realm roles

| Role | Grafana | IoT Bridge API | Tenant Portal | pgAdmin | RabbitMQ | KC CDM Admin | KC Provider Admin |
|---|---|---|---|---|---|---|---|
| `platform-admin` | ✅ Admin[^3] | ✅ Full[^3] | ✅ Admin view[^3] | ✗ | ✅ Administrator | ✅ Full[^4] | ✅ Full[^4] |
| `platform-operator` | 🔵 Editor[^3] | 👁 Read-only[^3] | 🔵 Operator view[^3] | ✗ | 👁 Monitoring[^5] | ✗ | ✗ |

**Footnotes**

[^1]: pgAdmin uses OIDC to authenticate any `cdm` realm user, but the database connection
      is shared and maps to the `postgres` superuser via `pg_service.conf`.  **In production,
      restrict pgAdmin access to `cdm-admin` only** by adding a `pgadmin` client scope tied
      to the `cdm-admin` role, or by deploying pgAdmin behind an additional role-check layer.

[^2]: `cdm-admin` does **not** automatically have Keycloak Admin Console access.  A superadmin
      must explicitly run `init-tenants.sh` to grant `realm-admin` on the `cdm` realm to the
      target user account, or promote the user via the Admin REST API.

[^3]: `provider` realm users access `cdm`-realm-protected services (Grafana, IoT Bridge API,
      Portal) through the **Grafana Identity Provider broker** (`grafana-broker` client in `cdm`
      realm).  The broker maps `platform-admin` → `cdm-admin` and `platform-operator` →
      `cdm-operator` via protocol mappers.

[^4]: `platform-admin` is identical to `KC_ADMIN_USER` / `${KC_ADMIN_USER}` — the master-realm
      superadmin.  `init-tenants.sh` grants `realm-admin` on both `cdm` and `provider` realms.

[^5]: The `rabbitmq.tag:monitoring` scope is registered in the `provider` realm but is **not**
      a default scope on the `rabbitmq-management` client.  `platform-operator` users receive
      monitoring-only access only if this scope is explicitly assigned to them.

---

## step-ca / PKI Access

step-ca (`/pki/`) does not use Keycloak OIDC.  Access is controlled by:

| Mechanism | Who | Purpose |
|---|---|---|
| JWK provisioner password (`STEP_CA_PROVISIONER_PASSWORD`) | IoT Bridge API service account | Sign device CSRs |
| Admin provisioner (`STEP_CA_ADMIN_PASSWORD`) | Platform admin (manual) | CA management, policy changes |
| ACME | Any service with DNS access | Automatic TLS cert issuance |

---

## Current User Assignments

The table below shows which users exist in the respective realms **at the time this
snapshot was generated**.  Re-run the script to refresh:

```bash
cd provider-stack
source .env
python3 keycloak/generate-access-matrix.py
```

### Default users (from realm templates)

#### `cdm` realm

| Username | Email | Roles |
|---|---|---|
| `cdm-admin` | *(template default)* | `cdm-admin` |
| `cdm-operator` | *(template default)* | `cdm-operator` |

#### `provider` realm

| Username | Email | Roles |
|---|---|---|
| `${KC_ADMIN_USER}` | *(env-set)* | `platform-admin` |
| `provider-operator` | *(template default)* | `platform-operator` |

!!! info "Run the script for live data"
    The table above reflects the realm templates only.  Users added or removed at runtime
    are visible only in the script output.

---

## Generating a Live Snapshot

The helper script queries the Keycloak Admin REST API and prints the current
user-to-endpoint access table as Markdown.

```bash
cd provider-stack

# Uses EXTERNAL_URL / KC_ADMIN_USER / KC_ADMIN_PASSWORD from .env
source .env
python3 keycloak/generate-access-matrix.py

# Override base URL (Codespaces)
python3 keycloak/generate-access-matrix.py https://<codespace>-8888.app.github.dev

# Pipe directly into the docs page section
python3 keycloak/generate-access-matrix.py > /tmp/matrix.md && echo "Done"
```

### What the script checks

1. Authenticates as master-realm admin against `/auth/realms/master/protocol/openid-connect/token`
2. Lists all users in the `cdm` realm with their effective realm roles
3. Lists all users in the `provider` realm with their effective realm roles
4. Maps each role to the per-endpoint access level (using the same logic as the matrix above)
5. Prints a Markdown table and a summary of any anomalies (unexpected roles, disabled users, etc.)
