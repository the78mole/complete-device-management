#!/usr/bin/env python3
"""
generate-access-matrix.py — CDM Provider Stack

Queries the Keycloak Admin REST API and prints a Markdown access matrix that
shows which users in the cdm and provider realms have which permissions on
each provider-stack endpoint.

Usage:
    # From the provider-stack directory with .env sourced:
    source .env && python3 keycloak/generate-access-matrix.py

    # Override the base URL:
    python3 keycloak/generate-access-matrix.py https://<host>-8888.app.github.dev

    # Redirect to file:
    python3 keycloak/generate-access-matrix.py > /tmp/access-matrix.md

Environment variables (all read from .env via `source`):
    EXTERNAL_URL        Base URL of the provider stack  (default: http://localhost:8888)
    KC_ADMIN_USER       Keycloak master-realm admin     (default: admin)
    KC_ADMIN_PASSWORD   Keycloak admin password         (default: changeme)
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


# ---------------------------------------------------------------------------
# Static access-level mapping
# Keys: realm role names.  Values per endpoint: human-readable access string.
# ---------------------------------------------------------------------------
ENDPOINT_ACCESS: dict[str, dict[str, str]] = {
    "grafana": {
        "cdm-admin":        "✅ Admin",
        "cdm-operator":     "🔵 Editor",
        "cdm-viewer":       "👁 Viewer",
        "platform-admin":   "✅ Admin (via broker)",
        "platform-operator":"🔵 Editor (via broker)",
    },
    "iot-bridge-api": {
        "cdm-admin":        "✅ Full",
        "cdm-operator":     "🔵 Read + deploy",
        "cdm-viewer":       "👁 Read-only",
        "platform-admin":   "✅ Full (via broker)",
        "platform-operator":"👁 Read-only (via broker)",
    },
    "tenant-portal": {
        "cdm-admin":        "✅ Admin view",
        "cdm-operator":     "🔵 Operator view",
        "cdm-viewer":       "👁 Viewer view",
        "platform-admin":   "✅ Admin view (via broker)",
        "platform-operator":"🔵 Operator view (via broker)",
    },
    "pgadmin": {
        # Any cdm user can log in; all get the shared postgres superuser connection
        "cdm-admin":        "⚠️ DB Superuser [^1]",
        "cdm-operator":     "⚠️ DB Superuser [^1]",
        "cdm-viewer":       "⚠️ DB Superuser [^1]",
    },
    "rabbitmq": {
        "platform-admin":   "✅ Administrator",
        "platform-operator":"👁 Monitoring [^5]",
    },
    "kc-cdm-admin": {
        # Only master-realm superadmin (= platform-admin) after init-tenants.sh
        "platform-admin":   "✅ Full [^4]",
    },
    "kc-provider-admin": {
        "platform-admin":   "✅ Full [^4]",
    },
}

ENDPOINT_LABELS: list[tuple[str, str]] = [
    ("grafana",          "Grafana"),
    ("iot-bridge-api",   "IoT Bridge API"),
    ("tenant-portal",    "Tenant Portal"),
    ("pgadmin",          "pgAdmin"),
    ("rabbitmq",         "RabbitMQ Mgmt"),
    ("kc-cdm-admin",     "KC CDM Admin"),
    ("kc-provider-admin","KC Provider Admin"),
]


def _no_access(endpoint: str, roles: list[str]) -> str:
    """Emit '✗' or a placeholder for empty role lists."""
    return "✗"


def access_for(roles: list[str], endpoint: str) -> str:
    mapping = ENDPOINT_ACCESS.get(endpoint, {})
    for role in roles:
        if role in mapping:
            return mapping[role]
    return "✗"


# ---------------------------------------------------------------------------
# Keycloak REST helpers (stdlib only)
# ---------------------------------------------------------------------------

def _request(url: str, *, method: str = "GET", data: bytes | None = None,
             headers: dict[str, str] | None = None) -> Any:
    req = Request(url, data=data, method=method, headers=headers or {})
    try:
        with urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())
    except HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise SystemExit(f"HTTP {exc.code} {exc.reason} for {url}\n{body}") from exc
    except URLError as exc:
        raise SystemExit(f"Cannot reach {url}: {exc.reason}") from exc


def get_admin_token(base: str, user: str, password: str) -> str:
    url = f"{base}/auth/realms/master/protocol/openid-connect/token"
    data = urlencode({
        "grant_type": "password",
        "client_id": "admin-cli",
        "username": user,
        "password": password,
    }).encode()
    result = _request(url, method="POST", data=data,
                      headers={"Content-Type": "application/x-www-form-urlencoded"})
    return result["access_token"]


def kc_get(base: str, path: str, token: str) -> Any:
    return _request(f"{base}/{path.lstrip('/')}",
                    headers={"Authorization": f"Bearer {token}"})


def get_users_with_roles(base: str, token: str, realm: str) -> list[dict]:
    users = kc_get(base, f"auth/admin/realms/{realm}/users?max=200&briefRepresentation=false", token)
    result = []
    for user in users:
        uid = user["id"]
        try:
            roles = kc_get(base, f"auth/admin/realms/{realm}/users/{uid}/role-mappings/realm", token)
        except SystemExit:
            roles = []
        filtered_roles = [r["name"] for r in roles
                          if not r["name"].startswith("default-roles-")
                          and not r["name"].startswith("uma_")]
        result.append({
            "username": user.get("username", ""),
            "email": user.get("email", "—"),
            "enabled": user.get("enabled", False),
            "roles": filtered_roles,
        })
    return sorted(result, key=lambda u: u["username"])


# ---------------------------------------------------------------------------
# Markdown output
# ---------------------------------------------------------------------------

def _enabled_badge(enabled: bool) -> str:
    return "" if enabled else " *(disabled)*"


def render_matrix(users_by_realm: dict[str, list[dict]]) -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines: list[str] = []

    lines.append(f"<!-- Generated by generate-access-matrix.py on {now} -->")
    lines.append("")
    lines.append(f"> **Snapshot generated:** {now}  ")
    lines.append("> Re-run `python3 keycloak/generate-access-matrix.py` to refresh.")
    lines.append("")

    header_cols = ["Realm", "Username", "Email", "Roles"] + [lbl for _, lbl in ENDPOINT_LABELS]
    lines.append("| " + " | ".join(header_cols) + " |")
    lines.append("|" + "|".join("---" for _ in header_cols) + "|")

    anomalies: list[str] = []

    for realm, users in users_by_realm.items():
        for user in users:
            username = user["username"]
            email = user["email"] or "—"
            enabled = user["enabled"]
            roles = user["roles"]
            roles_str = ", ".join(f"`{r}`" for r in roles) if roles else "*(none)*"

            access_cols = [access_for(roles, ep) for ep, _ in ENDPOINT_LABELS]

            # Flag anomalies
            if not enabled:
                anomalies.append(f"⚠️ `{realm}/{username}` is **disabled** but still exists.")
            if not roles:
                anomalies.append(f"ℹ️ `{realm}/{username}` has **no realm roles** assigned.")
            # pgAdmin superuser for non-admins is a security concern
            if realm == "cdm" and any(r in ("cdm-operator", "cdm-viewer") for r in roles):
                anomalies.append(
                    f"⚠️ `cdm/{username}` (`{roles_str}`) gets **postgres superuser** access "
                    "via pgAdmin — restrict to `cdm-admin` only in production."
                )

            row = [realm, username + _enabled_badge(enabled), email, roles_str] + access_cols
            lines.append("| " + " | ".join(row) + " |")

    if anomalies:
        lines.append("")
        lines.append("### Anomalies & Security Notes")
        lines.append("")
        for note in anomalies:
            lines.append(f"- {note}")

    return "\n".join(lines)


def render_full_page(users_by_realm: dict[str, list[dict]]) -> str:
    matrix = render_matrix(users_by_realm)
    return f"""# Access Matrix — Live Snapshot

This file is **auto-generated** by `provider-stack/keycloak/generate-access-matrix.py`.
For the canonical reference (including footnotes, endpoint descriptions, and role
explanations) see [access-matrix.md](access-matrix.md).

---

## Live User Access Matrix

{matrix}

---

## Legend

| Symbol | Meaning |
|---|---|
| ✅ | Full / Admin access |
| 🔵 | Editor / Write access |
| 👁 | Read-only / Viewer access |
| ⚠️ | Access granted but requires attention |
| ✗ | No access |

[^1]: pgAdmin grants all authenticated cdm realm users the shared `postgres` superuser
      connection via `pg_service.conf`.  Restrict to `cdm-admin` only in production.
[^4]: `platform-admin` = KC master-realm superadmin; `init-tenants.sh` grants realm-admin.
[^5]: `rabbitmq.tag:monitoring` is registered but not a default scope — assign explicitly.
"""


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    base_url = (
        sys.argv[1] if len(sys.argv) > 1
        else os.environ.get("EXTERNAL_URL", "http://localhost:8888").rstrip("/")
    )
    admin_user = os.environ.get("KC_ADMIN_USER", "admin")
    admin_password = os.environ.get("KC_ADMIN_PASSWORD", "changeme")

    print(f"[*] Connecting to {base_url} as {admin_user!r} ...", file=sys.stderr)

    token = get_admin_token(base_url, admin_user, admin_password)
    print("[*] Token obtained.", file=sys.stderr)

    users_by_realm: dict[str, list[dict]] = {}
    for realm in ("cdm", "provider"):
        print(f"[*] Fetching users from realm '{realm}' ...", file=sys.stderr)
        try:
            users_by_realm[realm] = get_users_with_roles(base_url, token, realm)
            print(f"    → {len(users_by_realm[realm])} user(s) found.", file=sys.stderr)
        except SystemExit as exc:
            print(f"    ✗ Could not fetch realm '{realm}': {exc}", file=sys.stderr)
            users_by_realm[realm] = []

    print("", file=sys.stderr)

    # Output full page to stdout
    print(render_full_page(users_by_realm))


if __name__ == "__main__":
    main()
