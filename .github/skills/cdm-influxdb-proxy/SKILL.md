# CDM Skill — InfluxDB OAuth2 Proxy & Token Injection

This document covers the InfluxDB access chain in the **provider-stack**: how
`oauth2-proxy` protects access, and how the `influxdb-token-injector` sidecar
transparently authenticates requests to InfluxDB.

---

## 1. Architecture overview

```
Browser
  │  HTTPS (port 8086, direct — SPA limitation)
  ▼
oauth2-proxy (provider-influxdb-proxy :4180)
  │  OIDC auth code flow against Keycloak cdm realm
  │  Validates session cookie; rejects unauthenticated requests
  ▼
influxdb-token-injector (provider-influxdb-token-injector :8087)
  │  Caddy reverse proxy — injects:  Authorization: Token <INFLUX_TOKEN>
  ▼
InfluxDB 2 (provider-influxdb :8086)
  │  Receives every request pre-authenticated with the admin API token
  │  → no second login screen shown to the user
```

### Why two proxies?

- **oauth2-proxy** handles human authentication (Keycloak OIDC).  It does not support
  injecting backend authentication headers — only session cookies.
- **InfluxDB** has its own authentication layer (admin token) and cannot be configured
  to trust an upstream proxy's identity assertion without a token.
- **Solution:** `influxdb-token-injector` (Caddy) sits between `oauth2-proxy` and
  `InfluxDB` and adds the `Authorization: Token …` header on every request.

---

## 2. Services

### `oauth2-proxy` service (`provider-influxdb-proxy`)

| Setting | Value | Notes |
|---|---|---|
| Image | `quay.io/oauth2-proxy/oauth2-proxy:v7.8.1` | |
| Upstream | `http://influxdb-token-injector:8087` | Must point to the injector, NOT directly to InfluxDB |
| Client ID | `influxdb-proxy` (in `cdm` realm) | Confidential OIDC client |
| Client Secret | `${INFLUXDB_PROXY_OIDC_SECRET}` | Copy from Keycloak after first boot |
| Cookie domain | set via `OAUTH2_PROXY_COOKIE_DOMAINS` | Must match the InfluxDB external URL domain |

**Codespaces-specific settings** (required for HTTPS cross-origin cookies):

```dotenv
INFLUX_PROXY_COOKIE_SECURE=true    # Must be true when served over HTTPS
INFLUX_PROXY_COOKIE_SAMESITE=none  # Required for Codespaces cross-site redirects
```

On localhost these default to `false` / `lax`.

### `influxdb-token-injector` service

| Setting | Value |
|---|---|
| Image | `caddy:2-alpine` |
| Internal port | `8087` |
| Upstream | `influxdb:8086` |
| Caddyfile | `provider-stack/monitoring/influxdb/token-injector/Caddyfile` |

---

## 3. Caddyfile — token injection

File: `provider-stack/monitoring/influxdb/token-injector/Caddyfile`

```caddy
:8087 {
    reverse_proxy influxdb:8086 {
        header_up >Authorization "Token {$INFLUX_TOKEN}"
    }
}
```

### Caddy variable substitution syntax

> **Critical:** In Caddyfile directives, use `{$VAR}` for environment variable substitution,
> **not** `{env.VAR}`.
>
> | Syntax | Works in | Why |
> |---|---|---|
> | `{$VAR}` | All directives, including `header_up` | Substituted at config load time |
> | `{env.VAR}` | Only in specific Caddy placeholders (e.g. logging) | Is a runtime placeholder — **not** substituted in header values |

### `>Authorization` vs `Authorization`

| Directive | Behaviour |
|---|---|
| `header_up >Authorization "Token …"` | **Sets** the header — replaces any existing value (correct) |
| `header_up Authorization "Token …"` | **Adds** the header — results in duplicate `Authorization` headers if the client already sent one |

Always use the `>` prefix in `header_up` to ensure the header is always replaced.

---

## 4. Environment variables

| Variable | Service | Description |
|---|---|---|
| `INFLUX_TOKEN` | `influxdb-token-injector` | InfluxDB admin API token (same as `INFLUXDB_ADMIN_TOKEN`) — injected as `Authorization: Token <value>` |
| `INFLUXDB_PROXY_OIDC_SECRET` | `influxdb-proxy` (oauth2-proxy) | Secret for the `influxdb-proxy` Keycloak OIDC client |
| `INFLUX_EXTERNAL_URL` | `influxdb-proxy` (oauth2-proxy) | Full external URL for the InfluxDB port (e.g. `https://<CODESPACE>-8086.app.github.dev`) |
| `INFLUX_PROXY_COOKIE_SECURE` | `influxdb-proxy` | `true` for HTTPS (Codespaces), `false` for localhost |
| `INFLUX_PROXY_COOKIE_SAMESITE` | `influxdb-proxy` | `none` for HTTPS cross-site (Codespaces), `lax` for localhost |

---

## 5. `docker-compose.yml` excerpt

```yaml
influxdb-proxy:
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.8.1
  environment:
    OAUTH2_PROXY_UPSTREAMS: http://influxdb-token-injector:8087    # ← injector, not influxdb
    OAUTH2_PROXY_COOKIE_SECURE: "${INFLUX_PROXY_COOKIE_SECURE:-false}"
    OAUTH2_PROXY_COOKIE_SAMESITE: "${INFLUX_PROXY_COOKIE_SAMESITE:-lax}"
    # ...
  depends_on:
    - influxdb-token-injector  # ← depends on injector

influxdb-token-injector:
  image: caddy:2-alpine
  volumes:
    - ./monitoring/influxdb/token-injector/Caddyfile:/etc/caddy/Caddyfile:ro
  environment:
    INFLUX_TOKEN: "${INFLUXDB_ADMIN_TOKEN}"
  depends_on:
    - influxdb
```

---

## 6. Login flow

1. User navigates to `https://<host>:8086` (port 8086, direct).
2. `oauth2-proxy` redirects to Keycloak `cdm` realm login.
3. User logs in with `cdm-admin` or `cdm-operator` credentials.
4. Keycloak redirects back; `oauth2-proxy` sets a session cookie and proxies the request upstream.
5. `influxdb-token-injector` adds `Authorization: Token <admin-token>` to every proxied request.
6. InfluxDB accepts the request — the user sees the InfluxDB UI directly without a second login screen.

**Credentials for the Keycloak login step:**

| Username | Password | Notes |
|---|---|---|
| `cdm-admin` | `changeme` (temporary) | Full access; change on first login |
| `cdm-operator` | `changeme` (temporary) | Operator access |

---

## 7. Troubleshooting

### oauth2-proxy "Rejecting invalid redirect"

```
[ERROR] Failed to make the request: Rejecting invalid redirect
```

**Cause:** `INFLUX_EXTERNAL_URL` or `EXTERNAL_URL` is set to `localhost` but the browser
is accessing via a Codespaces URL (`*.app.github.dev`).

**Fix:** Update `.env`:
```dotenv
EXTERNAL_URL=https://<CODESPACE_NAME>-8888.app.github.dev
INFLUX_EXTERNAL_URL=https://<CODESPACE_NAME>-8086.app.github.dev
```

### InfluxDB shows its own login screen after Keycloak auth

**Cause:** `oauth2-proxy` upstream points directly to `influxdb:8086` — the token-injector
service is not in the chain, so InfluxDB never receives an auth token.

**Fix:** Ensure `OAUTH2_PROXY_UPSTREAMS=http://influxdb-token-injector:8087`.

### Token injector returns 502 Bad Gateway

**Fix:** Check that the `influxdb-token-injector` container is running and that
`INFLUX_TOKEN` matches `INFLUXDB_ADMIN_TOKEN`:

```bash
docker compose -f provider-stack/docker-compose.yml logs influxdb-token-injector
docker compose -f provider-stack/docker-compose.yml exec influxdb-token-injector \
  wget -qO- --header="Authorization: Token $INFLUX_TOKEN" http://influxdb:8086/health
```
