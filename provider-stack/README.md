# Provider-Stack Setup (Codespaces / Dev)

This guide describes the complete, reproducible procedure for a **clean rebuild** of the
Provider-Stack in Codespaces — including initial cleanup, PKI initialization, and smoke test.

## Target State

At the end, all Provider services should be running stably with:

- `provider-step-ca` (`healthy`)
- `provider-keycloak` (`healthy`)
- `provider-rabbitmq` (`healthy`)
- `provider-timescaledb` (`healthy`)
- `provider-caddy`, `provider-grafana`, `provider-iot-bridge-api`, `provider-pgadmin`, `provider-telegraf` (`Up`)
- `provider-rabbitmq-cert-init` as a one-shot with `Exited (0)`

## 1) Create `.env` and set the Codespaces URL

```bash
cd provider-stack
cp .env.example .env
```

Set at least the following in `.env`:

```dotenv
EXTERNAL_URL=https://<codespace-name>-8888.app.github.dev
PGADMIN_EMAIL=admin@cdm-platform.dev
```

Notes:

- Get `<codespace-name>` by running `echo $CODESPACE_NAME`.
- `PGADMIN_EMAIL` must **not use a reserved domain** such as `.local`.

## 2) Initial Cleanup (complete)

```bash
docker compose down --volumes --remove-orphans
```

This starts from a clean state (containers, networks, and volumes removed).

## 3) Start `step-ca` first

```bash
docker compose up -d step-ca
```

Wait until the container is `healthy`:

```bash
docker compose ps step-ca
```

## 4) Initialize provisioners (important)

```bash
docker exec provider-step-ca /usr/local/bin/init-provisioners.sh
```

This creates (among others) the `iot-bridge` and `tenant-sub-ca-signer` provisioners.

## 5) Set the Root CA fingerprint

Read the fingerprint:

```bash
docker exec provider-step-ca sh -lc 'step certificate fingerprint /home/step/certs/root_ca.crt'
```

Set the output value in `.env` as `STEP_CA_FINGERPRINT=<value>`.

## 6) Start the full stack

```bash
docker compose up -d
```

Check status:

```bash
docker compose ps -a
```

## 7) Quick smoke test of endpoints

```bash
python3 - <<'PY'
import subprocess
base='http://localhost:8888'
endpoints=['/auth/','/grafana/','/api/health','/rabbitmq/','/pki/health','/pgadmin/']
print(f'Smoke test base: {base}')
for ep in endpoints:
    p = subprocess.run(['curl','-sS','-o','/dev/null','-w','%{http_code}', base+ep], capture_output=True, text=True, timeout=20)
    code = (p.stdout or '').strip() or '000'
    status = 'OK' if code.startswith(('2','3')) else 'FAIL'
    print(f'{status} {ep} -> HTTP {code}')
PY
```

Expected: all endpoints return `2xx` or `3xx`.

## Common Errors & Direct Fixes

### `provider-pgadmin`: invalid email address

Symptom: `admin@cdm.local` is rejected as a special-use/reserved domain.

Fix in `.env`:

```dotenv
PGADMIN_EMAIL=admin@cdm-platform.dev
```

Then restart:

```bash
docker compose up -d pgadmin
```

### `provider-rabbitmq-cert-init`: `STEP_CA_FINGERPRINT is not set`

Fix:

1. Read the fingerprint as described above.
2. Set it in `.env` at `STEP_CA_FINGERPRINT`.
3. Then run:

```bash
docker compose up -d rabbitmq-cert-init rabbitmq
```

### `provider-rabbitmq-cert-init`: `invalid value 'iot-bridge' for flag '--provisioner'`

Cause: The `iot-bridge` provisioner has not been created yet.

Fix:

```bash
docker exec provider-step-ca /usr/local/bin/init-provisioners.sh
docker compose up -d rabbitmq-cert-init rabbitmq
```

### `provider-telegraf` restart loop due to `outputs.postgresql`

With Telegraf `1.37`, certain fields (`create_metrics_table_if_not_exists`, `timescaledb`
block) are not available.

Fix: remove these fields from `monitoring/telegraf/telegraf.conf` (already applied in the
current state).

## Useful Quick Commands

```bash
# Overall status
docker compose ps -a

# Logs for a service
docker compose logs --no-color --tail=120 <service>

# Full reset
docker compose down --volumes --remove-orphans && docker compose up -d
```
