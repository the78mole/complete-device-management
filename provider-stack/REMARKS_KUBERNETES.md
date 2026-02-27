# Kubernetes — Abschätzung des Migrations-Aufwands für den Provider-Stack

Dieses Dokument analysiert, welche Anpassungen und Herausforderungen beim Deployment des
CDM Provider-Stacks auf Kubernetes zu erwarten sind.  Es dient als Entscheidungsgrundlage
und vorläufige Planung — kein fertiger Migrations-Guide.

---

## Zusammenfassung

| Kategorie | Aufwand | Risiko |
|---|---|---|
| Image-Build & Registry | niedrig | niedrig |
| Secrets & ConfigMaps | mittel | mittel |
| PersistentVolumeClaims | niedrig | niedrig |
| Networking & Ingress | hoch | hoch |
| Init-Container / Jobs | mittel | mittel |
| Keycloak (Start-Modus) | mittel | hoch |
| InfluxDB Direct-Port (SPA) | hoch | hoch |
| `depends_on` ersetzen | mittel | mittel |
| Kein Docker Compose Secrets API | mittel | mittel |
| RabbitMQ TLS (Shared Volume) | mittel | mittel |
| step-ca (Stateful PKI) | hoch | hoch |
| Skalierung / StatefulSets | hoch | hoch |

Gesamt-Einschätzung: **erheblicher Aufwand, mehrere Architektur-Entscheidungen nötig**.
Ein direktes `kompose convert` erzeugt lauffähige YAML-Manifeste, aber ohne alle hier
beschriebenen Anpassungen ist das Ergebnis **nicht produktionstauglich**.

---

## 1. Custom Docker Images — Build & Registry

Drei Services werden aus Quellcode gebaut und sind **nicht auf Docker Hub verfügbar**:

| Service | Dockerfile | Problem |
|---|---|---|
| `step-ca` | `provider-stack/step-ca/Dockerfile` | Build-Kontext ist das Repo-Root |
| `keycloak` | `provider-stack/keycloak/Dockerfile` | Realm-Templates werden zur Build-Zeit eingebaut |
| `iot-bridge-api` | `glue-services/iot-bridge-api/Dockerfile` | Anwendungs-Code |

**Konsequenz:**
- Eine Container Registry ist zwingend (ghcr.io, Docker Hub, ECR, GCR, …).
- Eine CI/CD-Pipeline (GitHub Actions, GitLab CI, …) muss Images bauen und pushen.
- Der `step-ca`-Build nutzt `context: ..` (Repo-Root als Kontext) — das muss in der
  CI-Pipeline mit `docker build -f provider-stack/step-ca/Dockerfile .` aus dem Repo-Root
  heraus aufgerufen werden.
- Bei Änderungen an Keycloak-Realm-Templates muss die Keycloak-Image-Version gestoßen
  werden (Tags!), sonst rollen Pods mit veralteten Templates aus.

---

## 2. Secrets

### Docker Compose Secrets → Kubernetes Secrets

Docker Compose kennt `secrets:` mit `file: ./step-ca/password.txt`.
In Kubernetes gibt es kein direktes Äquivalent — `password.txt` muss ein `Secret`-Objekt
werden und als Volume oder env-Variable eingemountet werden.

```yaml
# K8s Secret (base64-kodiert):
apiVersion: v1
kind: Secret
metadata:
  name: step-ca-password
stringData:
  password: "<inhalt von password.txt>"
```

Alle weiteren `.env`-Variablen (Passwörter, Tokens, OIDC-Secrets) müssen ebenfalls als
K8s-Secrets angelegt werden.  In der aktuellen Compose-Konfiguration gibt es
**über 20 Secrets**:

```
KC_ADMIN_PASSWORD, KC_DB_PASSWORD, STEP_CA_PASSWORD, STEP_CA_PROVISIONER_PASSWORD,
RABBITMQ_ADMIN_PASSWORD, RABBITMQ_MANAGEMENT_OIDC_SECRET,
INFLUX_TOKEN, INFLUX_PROXY_COOKIE_SECRET, INFLUXDB_PROXY_OIDC_SECRET,
GRAFANA_OIDC_SECRET, GRAFANA_BROKER_SECRET, BRIDGE_OIDC_SECRET,
PORTAL_OIDC_SECRET, PORTAL_SESSION_SECRET, PROVIDER_OPERATOR_PASSWORD, ...
```

**Empfehlung:** External Secrets Operator (ESO) mit einem Vault-Backend (HashiCorp Vault,
AWS Secrets Manager, Azure Key Vault) für produktionstaugliches Secret-Management.

---

## 3. PersistentVolumeClaims

Jedes benannte Docker-Volume wird ein `PersistentVolumeClaim`.  Im Provider-Stack gibt es
9 Volumes:

| Docker Volume | Typ | Empfohlener StorageClass |
|---|---|---|
| `keycloak-db-data` (PostgreSQL) | RWO | `standard` / SSD-backed |
| `influxdb-data` | RWO | SSD-backed (hohe I/O) |
| `influxdb-config` | RWO | `standard` |
| `grafana-data` | RWO | `standard` |
| `rabbitmq-data` | RWO | SSD-backed |
| `rabbitmq-tls` | RWO (**shared**, s. Abschnitt 8) | `standard` |
| `step-ca-data` (enthält CA-Keys) | RWO | verschlüsselt!, `encrypted-ssd` |
| `caddy-data` (Let's Encrypt cert cache) | RWO | `standard` |
| `iot-bridge-data` | RWO | `standard` |

Alle Volumes sind `ReadWriteOnce` — das ist kompatibel, schränkt aber **Horizontal Scaling
auf ein Replica pro Service** ein (sofern kein shared-filesystem wie NFS/EFS verwendet wird).

---

## 4. Networking — der kritischste Unterschied

### 4.1 Internes Service-Discovery

Docker Compose nutzt den Service-Namen direkt als DNS-Hostname (`keycloak:8080`,
`influxdb:8086`, …).  In Kubernetes werden `ClusterIP`-Services benötigt:

```yaml
# Beispiel: keycloak Service
apiVersion: v1
kind: Service
metadata:
  name: keycloak
spec:
  selector:
    app: keycloak
  ports:
    - port: 8080
      targetPort: 8080
```

Alle internen Hostnamen (`keycloak:8080`, `step-ca:9000`, `rabbitmq:15672`, usw.) bleiben
nutzbar, solange die Kubernetes-Services denselben Namen bekommen.

### 4.2 Ingress für externen Zugriff

Caddy als manuell konfigurierter Reverse Proxy wird in Kubernetes typischerweise durch
einen **Ingress Controller** (nginx-ingress, Traefik, Caddy Ingress, …) ersetzt.

Die aktuellen Pfad-Routing-Regeln aus dem Caddyfile müssen als `Ingress`-Ressource
abgebildet werden:

| Caddy-Pfad | K8s Ingress Path | Backend-Service |
|---|---|---|
| `/auth/*` | `/auth` | `keycloak:8080` |
| `/grafana/*` | `/grafana` | `grafana:3000` |
| `/api/*` (strip prefix) | `/api` | `iot-bridge-api:8000` |
| `/rabbitmq/*` | `/rabbitmq` | `rabbitmq:15672` |
| `/pki/*` (strip prefix, TLS upstream) | `/pki` | `step-ca:9000` |

**Besonderheit `/api/` strip prefix:** Caddy entfernt das `/api`-Präfix vor dem Forwarding.
In nginx-ingress: `nginx.ingress.kubernetes.io/rewrite-target: /$2` mit Regex-Pfad.
In Traefik: `StripPrefix`-Middleware.

### 4.3 InfluxDB — SPA Direct-Port Problem (kritisch!)

InfluxDB läuft auf **Port 8086 direkt** (kein Caddy-Pfad), weil die InfluxDB-SPA
hardcodierte absolute Pfade nutzt.  In Docker Compose wird Port 8086 über
`influxdb-proxy:4180` exponiert.

In Kubernetes gibt es **keine direkte Entsprechung zu `ports: - "8086:4180"`** auf der
Caddy-Ebene.  Optionen:

| Option | Aufwand | Nachteile |
|---|---|---|
| `NodePort` Service auf Port 8086 | niedrig | Nicht für Produktion, IP-abhängig |
| `LoadBalancer` Service mit external IP | mittel | Benötigt Cloud-LB pro Port; teuer |
| Separater Ingress auf Subdomain `influx.example.com` | mittel | Erfordert DNS-Eintrag; funktioniert gut |
| Caddy als Sidecar direkt im Pod (wie bisher) | niedrig | Nicht K8s-native |

**Empfehlung:** Subdomain-Ingress (`influx.example.com`) mit TLS via cert-manager.

### 4.4 RabbitMQ MQTT-Ports (1883, 5672, 8883)

Nicht-HTTP-Ports können nicht über einen Standard-HTTP-Ingress geroutet werden.
Optionen:
- `LoadBalancer` Services (bei Cloud-Providern gut unterstützt)
- nginx TCP/UDP proxy routing (nginx-ingress `tcp-services` ConfigMap)
- MetalLB für on-prem

---

## 5. `depends_on` mit `service_healthy` — kein direktes Äquivalent

Docker Compose wartet auf Health-Checks (`condition: service_healthy`).  Kubernetes hat
**kein natives `depends_on`** auf Pod-Ebene.  Lösungen:

| Problem | K8s-Lösung |
|---|---|
| Keycloak wartet auf keycloak-db | `initContainer` im Keycloak-Pod, der `pg_isready` pollt |
| rabbitmq-cert-init wartet auf step-ca | `Job` mit `initContainer` der step-ca-health prüft |
| iot-bridge-api wartet auf 4 Services | `readinessProbe` + Retry-Logik in der App |
| Alle Services warten auf Keycloak | `readinessProbe` in jedem Pod, der Keycloak braucht |

Die `readinessProbe` verhindert, dass ein Pod Traffic empfängt bevor er bereit ist — der
Pod startet aber ohne auf Abhängigkeiten zu warten.  Bei harten Boot-Reihenfolge-Anforderungen
(rabbitmq-cert-init → rabbitmq) sind `initContainers` oder Kubernetes `Jobs` nötig.

---

## 6. Keycloak: `start-dev` → `start` (Pflicht!)

Die aktuelle Konfiguration nutzt:

```yaml
command: >
  start-dev
  --import-realm
```

`start-dev` ist **nicht für Produktion geeignet** (kein Clustering, In-Memory-Caches,
reduzierte Sicherheit).  Für Kubernetes muss auf `start` umgestellt werden:

```yaml
command: >
  start
  --import-realm
  --optimized
```

Zusätzlich nötig:
- `KC_CACHE=ispn` (Infinispan-Clustering für Keycloak HA) oder `KC_CACHE=local` (Single-Node)
- `KC_DB=postgres` ist bereits konfiguriert ✅
- `KC_HOSTNAME` muss auf den Ingress-Hostnamen gesetzt sein
- `KC_PROXY=edge` oder `KC_PROXY_HEADERS=xforwarded` (`xforwarded` ist bereits gesetzt ✅)

Für echtes Keycloak-HA werden **mehrere Replicas** und das Infinispan-Clustering benötigt
(JGroups via DNS-Ping im K8s-Cluster).  Das ist erheblicher Zusatzaufwand.

**Empfehlung:** Offizieller [Keycloak Helm Chart](https://www.keycloak.org/operator/installation)
oder [Bitnami Keycloak Chart](https://github.com/bitnami/charts/tree/main/bitnami/keycloak)
als Ausgangspunkt — Realm-Templates als ConfigMap mounten.

---

## 7. step-ca — Stateful PKI (kritisch!)

step-ca ist besonders heikel in Kubernetes:

### 7.1 Single-Instance / kein HA

step-ca unterstützt keine horizontale Skalierung ohne externe Datenbank (z.B.
`badger v2` als DB-Backend statt `nosql`).  Es sollte als **StatefulSet mit 1 Replica**
deployed werden.

### 7.2 CA-Key im PersistentVolume

Der verschlüsselte Root-CA-Private-Key liegt im Volume `/home/step/secrets/`.  Das Volume
muss:
- Verschlüsselt (StorageClass mit encryption at rest)
- Backup-gesichert
- **Nicht** in einem ReadWriteMany-Volume (NFS) gespeichert werden

### 7.3 Erster Boot (`DOCKER_STEPCA_INIT_*`)

Die automatische CA-Initialisierung über `DOCKER_STEPCA_INIT_*`-Env-Variablen funktioniert
nur beim allerersten Start mit leerem Volume.  In Kubernetes muss das PVC rechtzeitig
vorhanden sein.  Bei erneutem Volume-Löschen wird die CA neu generiert — alle ausgestellten
Zertifikate werden ungültig.

**Empfehlung:** `step-ca` als `StatefulSet` mit 1 Replica und dedizierten PVC deployen.
CA-Key zusätzlich in einem Vault/HSM sichern (s. Security-Hinweise im step-ca SKILL).

### 7.4 ACME challenge für Caddy (intern)

In Docker Compose nutzt Caddy den ACME-Provisioner des internen step-ca für automatische
TLS-Zertifikate der Backend-Services.  In Kubernetes übernimmt `cert-manager` diese Rolle
für Service-TLS.  Der step-ca ACME-Provisioner kann für IoT-Device-Zertifikate weiterhin
genutzt werden.

---

## 8. RabbitMQ — Shared Volume (`rabbitmq-tls`)

In der aktuellen Architektur schreibt `rabbitmq-cert-init` TLS-Zertifikate in das Volume
`rabbitmq-tls`, das anschließend von `rabbitmq` gelesen wird.

In Kubernetes kann ein Volume nicht direkt zwischen einem `Job` (cert-init) und einem
`Pod` (rabbitmq) geteilt werden — nicht in dieser Form.  Alternativen:

1. **Init-Container im RabbitMQ-Pod:** cert-init wird als `initContainer` innerhalb des
   RabbitMQ-Pods ausgeführt, der dann das lokale Volume befüllt.
2. **Kubernetes Secret:** cert-init läuft als Job und schreibt das Zertifikat direkt in
   ein `Secret`; RabbitMQ mountet das Secret als Volume.  Benötigt RBAC-Berechtigung
   für den Job.
3. **cert-manager CertificateRequest:** cert-manager mit einem step-ca Issuer-Plugin kann
   TLS-Zertifikate direkt als K8s-Secrets ausstellen.

**Empfehlung:** Option 3 (cert-manager) oder Option 1 (initContainer) sind am
K8s-natürlichsten.

---

## 9. Externe URL & KC_HOSTNAME

In Docker Compose wird `EXTERNAL_URL` aus `.env` flexibel gesetzt.  In Kubernetes ergibt
sich die externe URL aus dem Ingress-Hostnamen.

`KC_HOSTNAME` muss korrekt gesetzt sein — Fehler hier führen zu kaputten Login-Seiten
(s. [Known Pitfall 7.5](.github/skills/cdm-keycloak/SKILL.md)).

```yaml
# In Keycloak Deployment env:
KC_HOSTNAME: "https://cdm.example.com/auth"
```

oauth2-proxy, Grafana, RabbitMQ und iot-bridge-api referenzieren `EXTERNAL_URL` in ihren
Environment-Variablen — all diese müssen auf den Ingress-Hostnamen aktualisiert werden.

---

## 10. Realm-Templates in Keycloak

Die Realm-JSON-Templates (`realm-cdm.json.tpl`, `realm-provider.json.tpl`) werden beim
Image-Build in die Keycloak-Image eingebaut.  In Kubernetes gibt es zwei Ansätze:

| Ansatz | Vorteil | Nachteil |
|---|---|---|
| Weiterhin im Image einbauen (aktuell) | Kein Refactoring nötig | Image muss bei Template-Änderung neu gebaut werden |
| Templates als ConfigMap mounten | Kein Image-Rebuild für Template-Änderungen | `docker-entrypoint.sh` muss aus dem Image laufen, Templates kommen von außen |

Der zweite Ansatz ist langfristig empfehlenswert:

```yaml
volumes:
  - name: realm-templates
    configMap:
      name: keycloak-realm-templates
volumeMounts:
  - name: realm-templates
    mountPath: /opt/keycloak/data/import-template
```

---

## 11. Helm Chart vs. Kustomize vs. Plain Manifests

Empfehlung: **Kustomize** für einfache Varianten, **Helm** wenn mehrere Umgebungen
(dev/staging/prod) deployt werden.

Sinnvolle Reihenfolge:
1. `kompose convert` als Ausgangspunkt → erzeugt rohe Manifeste
2. Manuell korrigieren (StatefulSets für Postgres/InfluxDB/RabbitMQ/step-ca)
3. Jobs für Einmal-Tasks (rabbitmq-cert-init)
4. initContainers für Boot-Reihenfolge-Abhängigkeiten
5. Helm Chart oder Kustomize-Overlays für `dev` / `prod`

Alternativ: existierende Community-Charts für Teilkomponenten nutzen:

| Service | Empfohlener Chart |
|---|---|
| PostgreSQL (Keycloak-DB) | `bitnami/postgresql` |
| Keycloak | `bitnami/keycloak` oder offizieller Operator |
| RabbitMQ | `bitnami/rabbitmq` |
| Grafana | `grafana/grafana` |
| InfluxDB | `influxdata/influxdb2` |
| cert-manager | `cert-manager/cert-manager` |

`step-ca` und `iot-bridge-api` müssen custom Charts bleiben.

---

## 12. RBAC & Service Accounts

Folgende Kubernetes-spezifische Berechtigungen werden nötig:

| Service | Benötigte Berechtigung |
|---|---|
| rabbitmq-cert-init (Job) | `create/update` auf `Secrets` (falls Zertifikat als Secret gespeichert wird) |
| iot-bridge-api | `read` auf `ConfigMaps` / `Secrets` für dynamische Konfiguration (optional) |
| cert-manager Issuer | Zugriff auf step-ca API für CertificateRequest-Signing |

---

## 13. Bekannte Fallstricke bei K8s-Migration

| Problem | Ursache | Lösung |
|---|---|---|
| Keycloak login-Seite kaputt | `KC_HOSTNAME` falsch (kein `/auth`-Suffix) | Exakt `https://<ingress-host>/auth` setzen |
| RabbitMQ Management SSO schlägt fehl | `oauth_provider_url` nicht browser-erreichbar | Auf Ingress-URL zeigen, nicht ClusterIP |
| InfluxDB SSO schlägt fehl | oauth2-proxy erwartet direkten Port statt Ingress-Pfad | Subdomain-Ingress oder LoadBalancer für InfluxDB |
| step-ca verliert CA nach PVC-Verlust | K8s-Volume gelöscht / PVC-Klasse ohne Reclaim | `persistentVolumeReclaimPolicy: Retain` setzen |
| Keycloak-Pods starten, DB ist nicht bereit | Kein `depends_on` | `initContainer` mit `pg_isready` |
| RabbitMQ TLS fehlt beim Start | cert-init Job noch nicht fertig | `initContainer` oder Job + Startup-Readiness-Probe |
| Caddy ACME-Zertifikate → cert-manager | Caddy braucht Port 80 für HTTP-Challenge | `cert-manager` HTTP-01-Solver stattdessen |

---

## 14. Schätzung des Aufwands

| Teilaufgabe | Aufwand (Manntage) |
|---|---|
| CI/CD Pipeline (Image build + push) | 1–2 |
| Basis-Manifeste (`kompose convert` + Korrekturen) | 2–3 |
| Keycloak `start-dev` → `start` + Realm-ConfigMaps | 2–3 |
| Ingress-Konfiguration (Pfad-Routing, InfluxDB-Subdomain) | 2–3 |
| RabbitMQ cert-init → initContainer / cert-manager | 1–2 |
| step-ca StatefulSet + PVC-Sicherung | 1–2 |
| Secrets → K8s Secrets / External Secrets Operator | 1–2 |
| Helm Chart oder Kustomize-Struktur | 3–5 |
| Testing + Debugging (HA, Failover) | 3–5 |
| **Gesamt** | **~16–27 Manntage** |

---

## 15. Empfohlene Migrations-Reihenfolge

1. **CI/CD**: Images bauen + in Registry pushen
2. **Secrets**: Alle Passwörter/Tokens als K8s-Secrets anlegen
3. **StatefulSets**: PostgreSQL, InfluxDB, RabbitMQ, step-ca
4. **Keycloak**: `start-dev` → `start`, Realm-Templates als ConfigMap
5. **InitContainer / Jobs**: Boot-Reihenfolge abbilden
6. **Ingress**: Pfad-Routing + Subdomain für InfluxDB
7. **EXTERNAL_URL / KC_HOSTNAME**: Auf Ingress-Hostnamen anpassen
8. **End-to-End-Test**: Login-Flow, RabbitMQ SSO, InfluxDB, step-ca Healthcheck
9. **cert-manager**: TLS für alle Ingress-Endpoints

---

## Referenzen

- [Keycloak Kubernetes Operator](https://www.keycloak.org/operator/installation)
- [cert-manager step-ca Issuer](https://github.com/smallstep/step-issuer)
- [RabbitMQ Cluster Operator](https://www.rabbitmq.com/kubernetes/operator/operator-overview)
- [External Secrets Operator](https://external-secrets.io/)
- [kompose](https://kompose.io/) — Docker Compose → K8s Manifeste
- CDM Skills: `.github/skills/cdm-keycloak/SKILL.md`, `.github/skills/cdm-step-ca/SKILL.md`
