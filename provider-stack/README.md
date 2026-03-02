# Provider-Stack Setup (Codespaces / Dev)

Diese Anleitung beschreibt den vollständigen, reproduzierbaren Ablauf für einen **sauberen Neuaufbau** des Provider-Stacks in Codespaces – inklusive Initial-Clean-Up, PKI-Initialisierung und Smoke-Test.

## Zielbild

Am Ende laufen die Provider-Services stabil mit:

- `provider-step-ca` (`healthy`)
- `provider-keycloak` (`healthy`)
- `provider-rabbitmq` (`healthy`)
- `provider-timescaledb` (`healthy`)
- `provider-caddy`, `provider-grafana`, `provider-iot-bridge-api`, `provider-pgadmin`, `provider-telegraf` (`Up`)
- `provider-rabbitmq-cert-init` als One-Shot mit `Exited (0)`

## 1) `.env` anlegen und Codespaces-URL setzen

```bash
cd provider-stack
cp .env.example .env
```

Setze in `.env` mindestens:

```dotenv
EXTERNAL_URL=https://<codespace-name>-8888.app.github.dev
PGADMIN_EMAIL=admin@cdm-platform.dev
```

Hinweise:

- `<codespace-name>` bekommst du mit `echo $CODESPACE_NAME`.
- `PGADMIN_EMAIL` darf **keine reservierte Domain** wie `.local` verwenden.

## 2) Initialer Clean-Up (vollständig)

```bash
docker compose down --volumes --remove-orphans
```

Damit startest du von einem sauberen Zustand (Container, Netzwerke und Volumes entfernt).

## 3) `step-ca` zuerst starten

```bash
docker compose up -d step-ca
```

Warte, bis der Container `healthy` ist:

```bash
docker compose ps step-ca
```

## 4) Provisioner initialisieren (wichtig)

```bash
docker exec provider-step-ca /usr/local/bin/init-provisioners.sh
```

Das legt u. a. `iot-bridge` und `tenant-sub-ca-signer` an.

## 5) Root-CA-Fingerprint setzen

Fingerprint auslesen:

```bash
docker exec provider-step-ca sh -lc 'step certificate fingerprint /home/step/certs/root_ca.crt'
```

Den ausgegebenen Wert in `.env` als `STEP_CA_FINGERPRINT=<wert>` eintragen.

## 6) Gesamten Stack starten

```bash
docker compose up -d
```

Status prüfen:

```bash
docker compose ps -a
```

## 7) Kurz-Smoke-Test der Endpoints

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

Erwartung: alle Endpoints liefern `2xx` oder `3xx`.

## Typische Fehler & direkte Fixes

### `provider-pgadmin`: invalid email address

Fehlerbild: `admin@cdm.local` wird als special-use/reserved domain abgewiesen.

Fix in `.env`:

```dotenv
PGADMIN_EMAIL=admin@cdm-platform.dev
```

Dann neu starten:

```bash
docker compose up -d pgadmin
```

### `provider-rabbitmq-cert-init`: `STEP_CA_FINGERPRINT is not set`

Fix:

1. Fingerprint wie oben auslesen.
2. In `.env` bei `STEP_CA_FINGERPRINT` setzen.
3. Danach:

```bash
docker compose up -d rabbitmq-cert-init rabbitmq
```

### `provider-rabbitmq-cert-init`: `invalid value 'iot-bridge' for flag '--provisioner'`

Ursache: Provisioner `iot-bridge` wurde noch nicht angelegt.

Fix:

```bash
docker exec provider-step-ca /usr/local/bin/init-provisioners.sh
docker compose up -d rabbitmq-cert-init rabbitmq
```

### `provider-telegraf` Restart-Loop wegen `outputs.postgresql`

Bei Telegraf `1.37` sind bestimmte Felder (`create_metrics_table_if_not_exists`, `timescaledb`-Block) nicht verfügbar.

Fix: diese Felder in `monitoring/telegraf/telegraf.conf` entfernen (bereits im aktuellen Stand umgesetzt).

## Nützliche Kurzbefehle

```bash
# Gesamtstatus
docker compose ps -a

# Logs eines Services
docker compose logs --no-color --tail=120 <service>

# Komplett neu aufsetzen
docker compose down --volumes --remove-orphans && docker compose up -d
```
