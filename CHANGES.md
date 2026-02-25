# Neue Architektur CDM

Die Erfahrungen mit der aktuellen monolithischen Architektur (alles in einem
`cloud-infrastructure/`-Compose-Stack) haben gezeigt, dass das System besser
partitioniert werden muss. Skalierung, Mandantentrennung und die Möglichkeit,
Tenant-Instanzen unabhängig vom Provider zu betreiben, erfordern eine klare
Trennung in zwei eigenständige Compose-Stacks.

---

## Das Provider Compose Setup

Dieses Setup wird zentral vom CDM-Betreiber betrieben und verwaltet die
angeschlossenen Tenant-Compose-Instanzen. Es stellt gemeinsam genutzte
Infrastruktur bereit und bildet den Vertrauensanker für die gesamte Plattform.

Die Initialisierung eines neuen Tenants erfolgt über die Management-API:
Der Tenant stellt einen JOIN-Request, ein Provider-Admin reviewed und approved
ihn manuell. Nach dem Approve werden Zertifikate ausgetauscht, die gegenseitiges
Vertrauen herstellen (mTLS für MQTT je Virtual Host pro Tenant sowie für die
CDM-Metriken).

**Komponenten:**

| Dienst | Funktion |
|---|---|
| Caddy | Provider Dashboard + Management API (löst nginx ab; native HTTPS, kein Proxy-Workaround) |
| Keycloak | Identity-Broker für alle Tenant-Realms; `provider`-Realm für Platform-Ops |
| RabbitMQ | Zentraler Broker: VHost `cdm-metrics` (Plattform) + je ein VHost pro Tenant (Gerätedaten) |
| InfluxDB + Grafana | Persistenz und Dashboards ausschließlich für CDM-eigene Metriken |
| step-ca | Root-CA + Intermediate-CA; signiert Tenant-Sub-CAs und Cluster-mTLS-Zertifikate |
| IoT Bridge API | Management-API: Tenant-Onboarding, RabbitMQ-vHost-Verwaltung, step-ca-Provisioner |

---

## Das Tenant Compose Setup

Mehrere dieser Instanzen verbinden sich mit dem Provider-Setup über dessen API
und warten auf den Approval. Nach Freischaltung läuft die gesamte Kommunikation
über den zentralen MQTT-Broker (mTLS) und die Management-API. Platform-Admins
und -Operatoren des CDM-Providers erhalten automatisch über Keycloak-Federation
einen passenden Zugang zur Tenant-Instanz.

**Komponenten:**

| Dienst | Funktion |
|---|---|
| Caddy | Tenant Dashboard + Management API (mit automatischem HTTPS) |
| Keycloak | Tenant-Realm; federated mit dem CDM-Provider-Realm; optionale Kunden-IAM-Anbindung (SAML/OIDC) |
| InfluxDB + Grafana | Zeitreihendaten und Dashboards für Kundensysteme; Daten fließen auch per MQTT zum Provider |
| ThingsBoard | Geräteverwaltung, Events, Rule Chains, Benachrichtigungen, OTA-Trigger |
| hawkBit | Software-Lifecycle-Management; Server-Endpunkt für SWupdate/RAUC |
| step-ca | Tenant-eigene Issuing-Sub-CA (signiert von der Provider-Root-CA); signiert Device-Zertifikate |
| WireGuard | VPN-Server; Devices als Clients; automatische Konfiguration via ThingsBoard-Regel |
| Terminal Proxy | Websocket-basierter Remote-Terminal-Zugang zu WireGuard-verbundenen Geräten |

---

## Umsetzungsplan

### Phase 1 – Provider-Stack extrahieren *(Refactoring)* ✅

Ausgangspunkt: aktueller `cloud-infrastructure/docker-compose.yml`.

| Aufgabe | Betroffene Dateien |
|---|---|
| Neues Verzeichnis `provider-stack/` anlegen | – |
| Caddy ersetzen nginx; `Caddyfile` mit automatischem HTTPS erstellen | `cloud-infrastructure/nginx/` → `provider-stack/caddy/` |
| Keycloak-Konfiguration übernehmen; nur `cdm`- und `provider`-Realm behalten | `keycloak/realms/realm-cdm.json.tpl`, `realm-provider.json.tpl` |
| RabbitMQ mit vHost-Initialisierung für `cdm-metrics` & Default-Tenant-vHost | `rabbitmq/rabbitmq.conf` |
| InfluxDB + Grafana für Provider-Metriken (eigene Volumes, kein Tenant-Zugriff) | `monitoring/` |
| step-ca als Root-CA + OIDC-Provisioner für Tenant-Sub-CA-Signing | `step-ca/` |
| IoT Bridge API als Management-API einbinden (Tenant-Onboarding-Workflow) | `glue-services/iot-bridge-api/` |
| `.env.example` für Provider-Stack anlegen | neu |

**Deliverable:** `provider-stack/docker-compose.yml` startet autark; bestehende
`glue-services/iot-bridge-api`-Tests bleiben grün.

---

### Phase 1.5 – Dokumentation & gh-pages auf neue Architektur anpassen *(Refactoring)* ✅

Die MkDocs-Dokumentation unter `docs/` beschreibt bisher die monolithische
`cloud-infrastructure/`-Welt.  Sie muss die neue Zwei-Stack-Architektur
(Provider-Stack + Tenant-Stack) vollständig reflektieren, bevor Phase 2
(Tenant-Stack) implementiert wird — damit Nutzer und Beitragende von Anfang an
das richtige mentale Modell haben.

#### Bestehende Dateien anpassen

| Datei | Aktueller Stand | Notwendige Änderungen |
|---|---|---|
| `docs/index.md` | Monolithische Übersicht; ein Stack, ein `docker compose up` | Stack-Topologie (Provider + Tenant) erklären; Links auf neue Installationsseiten; Quickstart-Hinweis auf beide Stacks |
| `docs/architecture/index.md` | Referenziert `cloud-infrastructure/`; Mermaid-Diagram zeigt alles in einem Block | High-Level-Diagram auf Provider-Stack / Tenant-Stack / Device-Stack aufteilen; Integration-Pillars aktualisieren (RabbitMQ-vHost-Routing, Caddy statt nginx) |
| `docs/architecture/pki.md` | Beschreibt step-ca im monolithischen Stack: Root-CA + IoT-Bridge-Provisioner | Zweistufige PKI-Hierarchie dokumentieren: Provider-Stack (Root-CA + Intermediate) → Tenant-Stack (Issuing-Sub-CA, per CSR bei Provider signiert); ACME-Endpunkt für Devices |
| `docs/architecture/iam.md` | Keycloak mit `cdm`, `provider`, `tenant1`, `tenant2` als fixe Realms; OIDC Identity Brokering | Realm-Federation beschreiben: Provider-Stack betreibt `cdm`- und `provider`-Realm; jede Tenant-Instanz wird als eigener Identity-Provider ins CDM-Realm federated; grafana-broker-Client entfällt zugunsten direkten Realm-Federation-Links |
| `docs/architecture/data-flow.md` | MQTT direkt auf ThingsBoard (8883); Telegraf fragt hawkBit ab | Datenpfade für neue Topologie beschreiben: Device → Tenant-MQTT (mTLS, Tenant-Broker) → RabbitMQ-vHost → Provider-InfluxDB; Provider-Telegraf konsumiert `cdm-metrics`-vHost; Tenant-Telegraf bleibt bei lokaler InfluxDB |
| `docs/installation/index.md` | Verweist auf `cloud-infrastructure.md` und `device-stack.md`; Port-Map für monolithischen Stack | Drei Installationspfade: Provider-Stack (neu), Tenant-Stack (Phase 2), Device-Stack; Port-Map auf neue Container-Namen (`provider-*`, `tenant-*`) aktualisieren; Abschnitt *GitHub Codespaces* ergänzen |
| `docs/installation/cloud-infrastructure.md` | Schritt-für-Schritt-Anleitung für `cloud-infrastructure/` | Umbenennen in `provider-stack.md`; Schritte auf `provider-stack/` anpassen; `cp .env.example .env` → neu; Healthcheck-Befehle auf `provider-*`-Container aktualisieren; Hinweis: Caddy löst nginx ab |
| `docs/getting-started/index.md` | Setzt die monolithische `cloud-infrastructure` voraus | Voraussetzung auf Provider-Stack (Phase 1) umstellen; Hinweis: Tenant-Stack-Quickstart kommt in Phase 2; Codespaces Single-Click-Open ergänzen |
| `docs/getting-started/first-device.md` | Enrollment gegen `cloud-infrastructure`-step-ca; MQTT auf ThingsBoard | Abschnitt *Provider-Stack first* einführen: step-ca fingerprint holen; Enrollment als Vorbereitung beschreiben; ThingsBoard-Schritte auf Phase-2-Tenant-Stack verschieben (als Vorausblick kennzeichnen) |
| `docs/getting-started/first-ota-update.md` | hawkBit direct im monolithischen Stack | Hinweis ergänzen: hawkBit ist Teil des Tenant-Stacks (Phase 2); Seite als *Phase 2 Preview* markieren |
| `docs/use-cases/index.md` | Drei Use Cases (Fleet, Security, Troubleshooting); Multi-Tenancy als Abschnitt | Use Case *Tenant Onboarding* ergänzen; Multi-Tenant-Abschnitt auf JOIN-Workflow + Realm-Federation aktualisieren; Operator-Day-Beispiel auf Provider- vs. Tenant-Operator unterscheiden |
| `docs/use-cases/fleet-management.md` | Beschreibt ThingsBoard + hawkBit-Dashboards im monolithischen Stack | ThingsBoard/hawkBit-Schritte auf Tenant-Stack lokalisieren; Provider-seitige Sicht (Grafana Provider-Dashboards) ergänzen; Mandantentrennung via RabbitMQ-vHost beschreiben |
| `docs/use-cases/security-incident-response.md` | Revoke + Isolate im monolithischen Stack | Zweistufigen Revoke-Pfad beschreiben: Tenant-Sub-CA (schnell, lokal im Tenant-Stack) vs. Provider-Root-CA (Eskalation); WireGuard-Peer-Entfernung im richtigen Stack verorten |
| `docs/use-cases/troubleshooting.md` | Troubleshooting-Befehle referenzieren `cdm-*`-Containernamen | Container-Namen auf `provider-*` / `tenant-*` aktualisieren; neuen Abschnitt *Stack-Kommunikation* (RabbitMQ vHost-Verbindungsprobleme) hinzufügen |
| `docs/workflows/device-provisioning.md` | Enrollment + MQTT-Connect gegen monolithischen Stack | Enrollment gegen Tenant-step-ca (Sub-CA) beschreiben; MQTT-Pfad über RabbitMQ-vHost einzeichnen; JOIN-Workflow referenzieren |
| `docs/workflows/monitoring.md` | Telegraf → InfluxDB direkt; Grafana im selben Stack | Doppeltes Monitoring beschreiben: Tenant-InfluxDB (Gerätedaten, lokal) + Provider-InfluxDB (Plattform-Health, aggregiert über RabbitMQ) |
| `docs/workflows/ota-updates.md` | hawkBit im monolithischen Stack | Hinweis: hawkBit → Tenant-Stack; Workflow bleibt gleich, aber Container-Namen ändern sich |
| `docs/workflows/remote-access.md` | WireGuard + Terminal Proxy im monolithischen Stack | WireGuard und Terminal-Proxy auf Tenant-Stack lokalisieren; Provider-Stack enthält keinen WireGuard-Server |

#### Neue Dateien anlegen

| Neue Datei | Inhalt |
|---|---|
| `docs/architecture/stack-topology.md` | Mermaid-Diagram der Zwei-Stack-Topologie (Provider + Tenant + Device); Netzwerk-Grenzen; Vertrauensbeziehungen (mTLS, Zertifikatshierarchie); Kommunikationswege (RabbitMQ-Verbindung Provider ↔ Tenant-MQTT, Keycloak-Federation) |
| `docs/installation/provider-stack.md` | Vollständige Schritt-für-Schritt-Anleitung: `git clone`, `cd provider-stack`, `.env` befüllen, `docker compose up -d`, Healthchecks, step-ca-Fingerprint ermitteln, Keycloak-Login testen |
| `docs/installation/tenant-stack.md` | Platzhalter für Phase 2; beschreibt den geplanten JOIN-Workflow, damit Leser das Gesamtbild verstehen; mit `!!! warning "Phase 2 – Work in Progress"` markieren |
| `docs/use-cases/tenant-onboarding.md` | JOIN-Request-Workflow aus Provider-Perspektive (Admin approve) und Tenant-Perspektive (`docker compose up`); Keycloak-Federation einrichten; RabbitMQ-vHost + Credentials automatisch anlegen; step-ca Sub-CA-CSR signieren |

#### `mkdocs.yml` – Nav-Änderungen

```yaml
nav:
  - Home: index.md
  - Installation:
    - Overview: installation/index.md
    - Provider Stack: installation/provider-stack.md       # neu (ersetzt cloud-infrastructure.md)
    - Tenant Stack: installation/tenant-stack.md           # neu (Phase 2 Preview)
    - Device Stack: installation/device-stack.md
  - Getting Started:
    - Quickstart: getting-started/index.md
    - Enroll Your First Device: getting-started/first-device.md
    - Trigger Your First OTA Update: getting-started/first-ota-update.md
  - Architecture:
    - Overview: architecture/index.md
    - Stack Topology: architecture/stack-topology.md       # neu
    - PKI (step-ca): architecture/pki.md
    - Identity & Access Management: architecture/iam.md
    - Data Flow: architecture/data-flow.md
  - Workflows:
    - Device Provisioning: workflows/device-provisioning.md
    - OTA Updates: workflows/ota-updates.md
    - Remote Access: workflows/remote-access.md
    - Monitoring & Telemetry: workflows/monitoring.md
  - Use Cases:
    - Overview: use-cases/index.md
    - Tenant Onboarding: use-cases/tenant-onboarding.md   # neu
    - Fleet Management: use-cases/fleet-management.md
    - Security Incident Response: use-cases/security-incident-response.md
    - Troubleshooting: use-cases/troubleshooting.md
```

**Deliverable:** `mkdocs build` schlägt nicht fehl; alle neuen und geänderten
Seiten sind im gh-pages-Branch sichtbar; kein `cloud-infrastructure`-spezifischer
Pfad mehr in der Navigation; neue Stack-Topologie-Seite mit vollständigem
Mermaid-Diagram ist vorhanden; `installation/tenant-stack.md` existiert als
Phase-2-Platzhalter mit korrekter Warnung.

---

### Phase 2 – Tenant-Stack als eigenständige Einheit *(Neuentwicklung)* ✅

> **Status: abgeschlossen** — `tenant-stack/` ist vollständig implementiert.
> `mkdocs build --strict` läuft fehlerfrei durch.

| Aufgabe | Betroffene Dateien |
|---|---|
| Neues Verzeichnis `tenant-stack/` anlegen | – |
| Caddy für Tenant-Dashboard konfigurieren (Sub-Domain oder Path) | `tenant-stack/caddy/` |
| Keycloak Tenant-Realm-Template generalisieren (`realm-tenant.json.tpl`) | aus `realm-tenant1/2.json.tpl` ableiten |
| ThingsBoard + hawkBit in den Tenant-Stack überführen | `cloud-infrastructure/` → `tenant-stack/` |
| step-ca Issuing-Sub-CA: Signing-Request gegen Provider-CA automatisieren | `tenant-stack/step-ca/` |
| WireGuard-Server-Konfiguration in den Tenant-Stack | `cloud-infrastructure/` → `tenant-stack/wireguard/` |
| Terminal Proxy in den Tenant-Stack | `glue-services/terminal-proxy/` → `tenant-stack/` |
| InfluxDB + Grafana für Tenant-Daten | `monitoring/` (Kopie/Anpassung) |
| `device-stack/` kompatibel halten (mTLS MQTT gegen Tenant-Broker) | `device-stack/` |
| `.env.example` für Tenant-Stack anlegen | neu |

**Deliverable:** `tenant-stack/docker-compose.yml` startet für `tenant1` autark
und verbindet sich über MQTT (mTLS) mit dem Provider-Stack.

---

### Phase 3 – JOIN-Workflow & Onboarding-API *(Neuentwicklung)* ✅

| Aufgabe | Details |
|---|---|
| JOIN-Request-Endpunkt in der IoT Bridge API | `POST /portal/admin/join-request/{id}` (unauthenticated) |
| Approval-Workflow im Admin Portal | Review + Approve/Reject UI in `admin_portal.py` + `admin_dashboard.html` |
| Zertifikatsaustausch automatisieren | step-ca: Provider signiert Tenant-Sub-CA-CSR via `tenant-sub-ca-signer`-Provisioner; Tenant erhält Root-CA-Zertifikat |
| **mTLS MQTT Bridge statt Passwort** | Tenant-Stack generiert MQTT-Bridge-Key+CSR, schickt CSR im JOIN-Request mit; Provider API signiert Zertifikat (CN=`{id}-mqtt-bridge`), gibt es im Bundle zurück – kein Passwort mehr |
| RabbitMQ MQTT+TLS (Port 8883) aktiviert | `provider-stack/rabbitmq/rabbitmq.conf`: MQTT-Plugin, TLS, EXTERNAL-Auth-Mechanismus (CN → Username) |
| RabbitMQ Server-Cert via step-ca | `provider-stack/rabbitmq/cert-init.sh` + `rabbitmq-cert-init`-Service (one-shot, `smallstep/step-cli`) |
| RabbitMQ EXTERNAL-User statt Passwort-User | `join.py`: `create_user(rmq_mqtt_user, "", tags="none")` + EXTERNAL auth |
| RabbitMQ vHost + EXTERNAL-User + Permissions automatisch anlegen | `RabbitMQClient.create_vhost/create_user/set_permissions` via approve-Endpunkt |
| **Keycloak-Federation Richtung korrigiert** | Provider KC (`cdm`-Realm) wird als IdP beim Tenant KC registriert (nicht umgekehrt) – CDM-Admins können sich damit direkt bei Tenant-Diensten (ThingsBoard, Grafana) per SSO anmelden |
| Keycloak OIDC-Client anlegen statt IdP registrieren | `join.py`: `_kc_create_federation_client()` erstellt `cdm-federation-{id}`-Client im Provider `cdm`-Realm, gibt Credentials im Bundle zurück |
| Tenant-Stack konfiguriert Provider KC als IdP | `init-sub-ca.sh` ruft Tenant KC Admin-API auf und registriert `cdm-provider`-IdP; Credentials in `/home/step/join-bundle/keycloak-federation.env` |
| Persistenter JOIN-Request-Store | JSON-Datei unter `JOIN_REQUESTS_DB_PATH=/data/join_requests.json` (Volume) |
| `app/clients/join_store.py` | Async-safe Read/Write für den JSON-Store |
| `app/routers/join.py` | Alle JOIN-Endpunkte inkl. Statuspolling, MQTT-CSR-Signing |
| `provider-stack/step-ca/` | Neues Dockerfile (Repo-Root als Build-Context) + `init-provisioners.sh` mit Sub-CA-Provisioner (`tenant-sub-ca-signer`) + Template `tenant-sub-ca.tpl` |
| `tenant-stack/step-ca/init-sub-ca.sh` | Vollständig auf JOIN-API umgestellt; generiert zusätzlich MQTT-Bridge-Key+CSR; installiert empfangenes `mqtt_bridge_cert` in `/home/step/mqtt-bridge/` |
| `docs/use-cases/tenant-onboarding.md` | Vollständige Dokumentation inkl. API-Referenz und mTLS-Architektur |

---

### Phase 4 – Device Stack anpassen *(Anpassung)* ✅

| Aufgabe | Details |
|---|---|
| `docker-compose.yml` auf Tenant-Stack umgestellt | Kommentare, Defaults und Abhängigkeiten auf Tenant-Stack angepasst; `HAWKBIT_URL` default auf `…:8888/hawkbit`; `BRIDGE_API_URL` default auf `…:8888/api` |
| `.env.example` vollständig überarbeitet | `TENANT_ID` als primäre Variable; kommentierte Tenant-Stack-Endpunkte; `STEP_CA_FINGERPRINT` erklärt als Tenant Sub-CA (nicht Provider Root CA) |
| Bootstrap gegen Tenant Sub-CA | `enroll.sh`: `TENANT_ID` + `STEP_CA_URL` hinzugefügt; TLS-Bootstrap via `step ca bootstrap --fingerprint` wenn `STEP_CA_URL` gesetzt; Enrollment-Endpunkt bleibt `/devices/{id}/enroll` (Tenant IoT Bridge API) |
| MQTT-Endpunkt auf Tenant ThingsBoard | `telegraf.conf`: `HAWKBIT_TENANT` → `TENANT_ID`; MQTT-Topic `cdm/$TENANT_ID/$DEVICE_ID/sensors`; `publish-telemetry.sh`: Kommentare auf Tenant ThingsBoard aktualisiert |
| WireGuard-Client | `wg-client.sh` war bereits korrekt (liest `wg0.conf` aus dem Volume, das Bootstrap via Tenant API befüllt) |
| OTA-Polling gegen Tenant hawkBit | `ddi-poll.sh`: Kommentare auf Tenant hawkBit aktualisiert; `rauc-hawkbit-updater.conf`: TLS aktiviert (`ssl = true`, `ssl_verify = true`), Cert-Pfade auf `/certs/` Volume |

**Deliverable:** Ein simuliertes Gerät (`device-stack/docker-compose.yml`) verbindet
sich vollständig mit einer Tenant-Instanz (PKI, MQTT, WireGuard, OTA).

---

### Phase 5 – Altstack entfernen & CI *(Abschluss)* ✅

> **Status: abgeschlossen** — `cloud-infrastructure/` mit Deprecation-`README.md` versehen;
> `README.md` auf neue Stack-Struktur umgestellt (Phase-2-Kennzeichnungen entfernt, Tenant-Stack
> als vollständig dokumentiert); CI-Workflow auf `provider-stack/` + `tenant-stack/` +
> `device-stack/` Compose-Validierung umgestellt (cloud-infrastructure entfernt).

| Aufgabe | Details |
|---|---|
| `cloud-infrastructure/` auf Kompatibilitäts-Shim reduzieren oder entfernen | `cloud-infrastructure/README.md` mit Deprecation-Hinweis und Migrationsleitfaden erstellt |
| README.md auf neue Stack-Struktur umstellen | Phase-2-Kennzeichnungen entfernt; Tenant-Stack-Quickstart-Schritt ergänzt; Mermaid-Diagram bereinigt |
| GitHub Actions / CI für beide Stacks (Lint, Build, Smoke-Test) | `.github/workflows/ci.yml`: `validate-docker-compose` prüft jetzt `provider-stack/`, `tenant-stack/` und `device-stack/` (je mit `cp .env.example .env`) |
| Abschluss `docs/` (Phase-2-Platzhalter durch echte Inhalte ersetzen) | `docs/installation/tenant-stack.md` und `docs/use-cases/tenant-onboarding.md` wurden in Phase 2 & 3 vollständig ausgefüllt |

---

### Getroffene Architekturentscheidungen

Die folgenden Punkte, die ursprünglich als offene Fragen notiert waren, wurden
bereits entschieden und implementiert:

| Entscheidung | Gewählte Option | Begründung |
|---|---|---|
| **Proxy** | **Caddy** (löst nginx ab) | Automatisches HTTPS via ACME; kein manuelles Cert-Management; einfacheres Caddyfile vs. nginx.conf |
| **ThingsBoard** | Im **Tenant-Stack** | Jeder Tenant betreibt eigene ThingsBoard-Instanz → vollständige Datenisolation; Provider-Stack wird schlank gehalten |
| **RabbitMQ-Isolation** | **vHost pro Tenant** auf zentralem Broker | Ausreichende Isolation; deutlich geringerer Betriebsaufwand als separater Broker; Broker im Provider-Stack, vHosts per API via IoT Bridge provisioniert |
| **Keycloak Federation** | **Provider KC als IdP beim Tenant** | Tenant KC registriert Provider `cdm`-Realm als OIDC-IdP → CDM-Admins können sich direkt bei Tenant-Diensten anmelden; Tenant-KC bleibt unabhängig für eigene Kunden-User |

