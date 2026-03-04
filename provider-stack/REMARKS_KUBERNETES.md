# Kubernetes — Migration Effort Estimate for the Provider-Stack

This document analyses the adjustments and challenges to expect when deploying the
CDM Provider-Stack on Kubernetes.  It serves as a decision-making basis and preliminary
planning — not a finished migration guide.

---

## Summary

| Category | Effort | Risk |
|---|---|---|
| Image Build & Registry | low | low |
| Secrets & ConfigMaps | medium | medium |
| PersistentVolumeClaims | low | low |
| Networking & Ingress | high | high |
| Init Containers / Jobs | medium | medium |
| Keycloak (start mode) | medium | high |
| TimescaleDB (StatefulSet) | medium | medium |
| Replacing `depends_on` | medium | medium |
| No Docker Compose Secrets API | medium | medium |
| RabbitMQ TLS (Shared Volume) | medium | medium |
| step-ca (Stateful PKI) | high | high |
| Scaling / StatefulSets | high | high |

Overall assessment: **significant effort, several architectural decisions required**.
A direct `kompose convert` produces runnable YAML manifests, but without all the
adjustments described here the result is **not production-ready**.

---

## 1. Custom Docker Images — Build & Registry

Three services are built from source and are **not available on Docker Hub**:

| Service | Dockerfile | Problem |
|---|---|---|
| `step-ca` | `provider-stack/step-ca/Dockerfile` | Build context is the repo root |
| `keycloak` | `provider-stack/keycloak/Dockerfile` | Realm templates are embedded at build time |
| `iot-bridge-api` | `glue-services/iot-bridge-api/Dockerfile` | Application code |

**Consequence:**
- A container registry is mandatory (ghcr.io, Docker Hub, ECR, GCR, …).
- A CI/CD pipeline (GitHub Actions, GitLab CI, …) must build and push images.
- The `step-ca` build uses `context: ..` (repo root as context) — the CI pipeline must
  call `docker build -f provider-stack/step-ca/Dockerfile .` from the repo root.
- When Keycloak realm templates change, the Keycloak image version must be bumped
  (tags!), otherwise pods roll out with stale templates.

---

## 2. Secrets

### Docker Compose Secrets → Kubernetes Secrets

Docker Compose uses `secrets:` with `file: ./step-ca/password.txt`.
Kubernetes has no direct equivalent — `password.txt` must become a `Secret` object
and be mounted as a volume or injected as an environment variable.

```yaml
# K8s Secret (base64-encoded):
apiVersion: v1
kind: Secret
metadata:
  name: step-ca-password
stringData:
  password: "<contents of password.txt>"
```

All other `.env` variables (passwords, tokens, OIDC secrets) must also be created as
K8s Secrets.  In the current Compose configuration there are **more than 20 secrets**:

```
KC_ADMIN_PASSWORD, KC_DB_PASSWORD, STEP_CA_PASSWORD, STEP_CA_PROVISIONER_PASSWORD,
RABBITMQ_ADMIN_PASSWORD, RABBITMQ_MANAGEMENT_OIDC_SECRET,
TSDB_PASSWORD, GRAFANA_OIDC_SECRET, GRAFANA_BROKER_SECRET, BRIDGE_OIDC_SECRET,
PORTAL_OIDC_SECRET, PORTAL_SESSION_SECRET, PROVIDER_OPERATOR_PASSWORD, ...
```

**Recommendation:** Use the External Secrets Operator (ESO) with a Vault backend
(HashiCorp Vault, AWS Secrets Manager, Azure Key Vault) for production-grade secret management.

---

## 3. PersistentVolumeClaims

Each named Docker volume becomes a `PersistentVolumeClaim`.  The Provider-Stack has
8 volumes:

| Docker Volume | Type | Recommended StorageClass |
|---|---|---|
| `keycloak-db-data` (PostgreSQL) | RWO | `standard` / SSD-backed |
| `timescaledb-data` (TimescaleDB) | RWO | SSD-backed (high I/O) |
| `grafana-data` | RWO | `standard` |
| `rabbitmq-data` | RWO | SSD-backed |
| `rabbitmq-tls` | RWO (**shared**, see section 8) | `standard` |
| `step-ca-data` (contains CA keys) | RWO | encrypted!, `encrypted-ssd` |
| `caddy-data` (Let's Encrypt cert cache) | RWO | `standard` |
| `iot-bridge-data` | RWO | `standard` |

All volumes are `ReadWriteOnce` — this is compatible but limits **horizontal scaling to
one replica per service** (unless a shared filesystem like NFS/EFS is used).

---

## 4. Networking — the Most Critical Difference

### 4.1 Internal Service Discovery

Docker Compose uses the service name directly as a DNS hostname (`keycloak:8080`,
`timescaledb:5432`, …).  Kubernetes requires `ClusterIP` Services:

```yaml
# Example: keycloak Service
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

All internal hostnames (`keycloak:8080`, `step-ca:9000`, `rabbitmq:15672`, `timescaledb:5432`, etc.) remain
usable as long as the Kubernetes Services get the same names.

### 4.2 Ingress for External Access

Caddy as a manually configured reverse proxy is typically replaced in Kubernetes by an
**Ingress Controller** (nginx-ingress, Traefik, Caddy Ingress, …).

The current path-routing rules from the Caddyfile must be mapped as `Ingress` resources:

| Caddy Path | K8s Ingress Path | Backend Service |
|---|---|---|
| `/auth/*` | `/auth` | `keycloak:8080` |
| `/grafana/*` | `/grafana` | `grafana:3000` |
| `/api/*` (strip prefix) | `/api` | `iot-bridge-api:8000` |
| `/rabbitmq/*` | `/rabbitmq` | `rabbitmq:15672` |
| `/pki/*` (strip prefix, TLS upstream) | `/pki` | `step-ca:9000` |

**Note on `/api/` strip prefix:** Caddy removes the `/api` prefix before forwarding.
In nginx-ingress: `nginx.ingress.kubernetes.io/rewrite-target: /$2` with a regex path.
In Traefik: `StripPrefix` middleware.

### 4.3 TimescaleDB — StatefulSet & Data Persistence

TimescaleDB (a PostgreSQL extension) replaces InfluxDB as the time-series backend.  Unlike
the previous InfluxDB setup, TimescaleDB exposes a standard **PostgreSQL port 5432** which
routes cleanly through a K8s `ClusterIP` Service — no direct-port SPA workaround is needed.

Key K8s considerations:

| Topic | Recommendation |
|---|---|
| Deployment type | `StatefulSet` with 1 replica (no built-in HA) |
| Storage | `ReadWriteOnce` PVC, SSD-backed StorageClass |
| Backups | Use `pg_dump` CronJob or a managed Postgres service |
| HA | For HA: use [Crunchy Postgres Operator](https://access.crunchydata.com/documentation/postgres-operator/) or managed cloud Postgres |
| Community chart | `bitnami/postgresql` with TimescaleDB image `timescale/timescaledb:latest-pg17` |

### 4.4 RabbitMQ MQTT Ports (1883, 5672, 8883)

Non-HTTP ports cannot be routed through a standard HTTP Ingress.
Options:
- `LoadBalancer` Services (well-supported with cloud providers)
- nginx TCP/UDP proxy routing (nginx-ingress `tcp-services` ConfigMap)
- MetalLB for on-premises deployments

---

## 5. `depends_on` with `service_healthy` — No Direct Equivalent

Docker Compose waits for health checks (`condition: service_healthy`).  Kubernetes has
**no native `depends_on`** at the Pod level.  Solutions:

| Problem | K8s Solution |
|---|---|
| Keycloak waits for keycloak-db | `initContainer` in the Keycloak Pod polling `pg_isready` |
| rabbitmq-cert-init waits for step-ca | `Job` with an `initContainer` checking step-ca health |
| iot-bridge-api waits for 4 services | `readinessProbe` + retry logic in the app |
| All services wait for Keycloak | `readinessProbe` in every Pod that requires Keycloak |

The `readinessProbe` prevents a Pod from receiving traffic before it is ready — but the
Pod starts without waiting for its dependencies.  For hard boot-order requirements
(rabbitmq-cert-init → rabbitmq), `initContainers` or Kubernetes `Jobs` are required.

---

## 6. Keycloak: `start-dev` → `start` (mandatory!)

The current configuration uses:

```yaml
command: >
  start-dev
  --import-realm
```

`start-dev` is **not suitable for production** (no clustering, in-memory caches, reduced
security).  For Kubernetes it must be switched to `start`:

```yaml
command: >
  start
  --import-realm
  --optimized
```

Additionally required:
- `KC_CACHE=ispn` (Infinispan clustering for Keycloak HA) or `KC_CACHE=local` (single node)
- `KC_DB=postgres` is already configured ✅
- `KC_HOSTNAME` must be set to the Ingress hostname
- `KC_PROXY=edge` or `KC_PROXY_HEADERS=xforwarded` (`xforwarded` is already set ✅)

For true Keycloak HA, **multiple replicas** and Infinispan clustering are required
(JGroups via DNS-Ping in the K8s cluster).  This involves significant additional effort.

**Recommendation:** Use the official [Keycloak Helm Chart](https://www.keycloak.org/operator/installation)
or the [Bitnami Keycloak Chart](https://github.com/bitnami/charts/tree/main/bitnami/keycloak)
as a starting point — mount realm templates as a ConfigMap.

---

## 7. step-ca — Stateful PKI (critical!)

step-ca is particularly delicate in Kubernetes:

### 7.1 Single Instance / No HA

step-ca does not support horizontal scaling without an external database (e.g.
`badger v2` as a DB backend instead of `nosql`).  It should be deployed as a
**StatefulSet with 1 replica**.

### 7.2 CA Key in PersistentVolume

The encrypted Root CA private key lives in the volume `/home/step/secrets/`.  That volume
must be:
- Encrypted (StorageClass with encryption at rest)
- Backed up
- **Not** stored in a ReadWriteMany volume (NFS)

### 7.3 First Boot (`DOCKER_STEPCA_INIT_*`)

Automatic CA initialisation via `DOCKER_STEPCA_INIT_*` environment variables only works
on the very first start with an empty volume.  In Kubernetes the PVC must be present in
time.  If the volume is deleted and recreated, the CA is regenerated and all previously
issued certificates become invalid.

**Recommendation:** Deploy `step-ca` as a `StatefulSet` with 1 replica and a dedicated PVC.
Additionally back up the CA key in a Vault/HSM (see security notes in the step-ca SKILL).

### 7.4 ACME Challenge for Caddy (internal)

In Docker Compose, Caddy uses the ACME provisioner of the internal step-ca for automatic
TLS certificates for backend services.  In Kubernetes, `cert-manager` takes over this role
for service TLS.  The step-ca ACME provisioner can still be used for IoT device
certificates.

---

## 8. RabbitMQ — Shared Volume (`rabbitmq-tls`)

In the current architecture, `rabbitmq-cert-init` writes TLS certificates into the
`rabbitmq-tls` volume, which is then read by `rabbitmq`.

In Kubernetes a volume cannot be directly shared between a `Job` (cert-init) and a
`Pod` (rabbitmq) in this way.  Alternatives:

1. **Init Container in the RabbitMQ Pod:** cert-init runs as an `initContainer` inside
   the RabbitMQ Pod, populating the local volume before the main container starts.
2. **Kubernetes Secret:** cert-init runs as a Job and writes the certificate directly
   into a `Secret`; RabbitMQ mounts the Secret as a volume.  Requires RBAC permissions
   for the Job.
3. **cert-manager CertificateRequest:** cert-manager with a step-ca Issuer plugin can
   issue TLS certificates directly as K8s Secrets.

**Recommendation:** Option 3 (cert-manager) or Option 1 (initContainer) are the most
Kubernetes-native approaches.

---

## 9. External URL & KC_HOSTNAME

In Docker Compose, `EXTERNAL_URL` is set flexibly via `.env`.  In Kubernetes, the
external URL is derived from the Ingress hostname.

`KC_HOSTNAME` must be set correctly — errors here cause broken login pages
(see [Known Pitfall 7.5](.github/skills/cdm-keycloak/SKILL.md)).

```yaml
# In Keycloak Deployment env:
KC_HOSTNAME: "https://cdm.example.com/auth"
```

oauth2-proxy, Grafana, RabbitMQ, and iot-bridge-api reference `EXTERNAL_URL` in their
environment variables — all of these must be updated to the Ingress hostname.

---

## 10. Realm Templates in Keycloak

The realm JSON templates (`realm-cdm.json.tpl`, `realm-provider.json.tpl`) are embedded
in the Keycloak image at build time.  In Kubernetes there are two approaches:

| Approach | Advantage | Disadvantage |
|---|---|---|
| Keep embedding in the image (current) | No refactoring needed | Image must be rebuilt on every template change |
| Mount templates as a ConfigMap | No image rebuild for template changes | `docker-entrypoint.sh` must run from the image; templates come from outside |

The second approach is recommended long-term:

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

Recommendation: **Kustomize** for simple variants, **Helm** when deploying multiple
environments (dev/staging/prod).

Suggested order:
1. `kompose convert` as a starting point → generates raw manifests
2. Manual corrections (StatefulSets for Postgres/TimescaleDB/RabbitMQ/step-ca)
3. Jobs for one-off tasks (rabbitmq-cert-init)
4. initContainers for boot-order dependencies
5. Helm Chart or Kustomize overlays for `dev` / `prod`

Alternatively, use existing community charts for sub-components:

| Service | Recommended Chart |
|---|---|
| PostgreSQL (Keycloak DB) | `bitnami/postgresql` |
| Keycloak | `bitnami/keycloak` or official Operator |
| RabbitMQ | `bitnami/rabbitmq` |
| Grafana | `grafana/grafana` |
| TimescaleDB | `timescale/timescaledb` (PostgreSQL-based) |
| cert-manager | `cert-manager/cert-manager` |

`step-ca` and `iot-bridge-api` must remain custom charts.

---

## 12. RBAC & Service Accounts

The following Kubernetes-specific permissions are required:

| Service | Required Permission |
|---|---|
| rabbitmq-cert-init (Job) | `create/update` on `Secrets` (if certificate is stored as a Secret) |
| iot-bridge-api | `read` on `ConfigMaps` / `Secrets` for dynamic configuration (optional) |
| cert-manager Issuer | Access to the step-ca API for CertificateRequest signing |

---

## 13. Known Pitfalls in K8s Migration

| Problem | Cause | Solution |
|---|---|---|
| Keycloak login page broken | `KC_HOSTNAME` wrong (missing `/auth` suffix) | Set exactly `https://<ingress-host>/auth` |
| RabbitMQ Management SSO fails | `oauth_provider_url` not browser-reachable | Point to Ingress URL, not ClusterIP |
| pgAdmin pods fail to start | Keycloak OIDC proxy misconfigured | Set correct `KC_HOSTNAME` in pgadmin-oidc-proxy env |
| step-ca loses CA after PVC loss | K8s volume deleted / PVC class without reclaim | Set `persistentVolumeReclaimPolicy: Retain` |
| Keycloak pods start, DB not ready | No `depends_on` | `initContainer` with `pg_isready` |
| RabbitMQ TLS missing at start | cert-init Job not finished yet | `initContainer` or Job + startup readiness probe |
| Caddy ACME certs → cert-manager | Caddy needs port 80 for HTTP challenge | Use `cert-manager` HTTP-01 solver instead |

---

## 14. Effort Estimate

| Sub-task | Effort (person-days) |
|---|---|
| CI/CD pipeline (image build + push) | 1–2 |
| Base manifests (`kompose convert` + corrections) | 2–3 |
| Keycloak `start-dev` → `start` + Realm ConfigMaps | 2–3 |
| Ingress configuration (path routing, pgAdmin sub-path) | 1–2 |
| RabbitMQ cert-init → initContainer / cert-manager | 1–2 |
| step-ca StatefulSet + PVC backup | 1–2 |
| Secrets → K8s Secrets / External Secrets Operator | 1–2 |
| Helm Chart or Kustomize structure | 3–5 |
| Testing + debugging (HA, failover) | 3–5 |
| **Total** | **~16–27 person-days** |

---

## 15. Recommended Migration Order

1. **CI/CD**: Build images and push to registry
2. **Secrets**: Create all passwords/tokens as K8s Secrets
3. **StatefulSets**: PostgreSQL (Keycloak DB), TimescaleDB, RabbitMQ, step-ca
4. **Keycloak**: `start-dev` → `start`, realm templates as ConfigMap
5. **InitContainers / Jobs**: Reproduce boot order
6. **Ingress**: Path routing + sub-path for pgAdmin
7. **EXTERNAL_URL / KC_HOSTNAME**: Update to Ingress hostname
8. **End-to-end test**: Login flow, RabbitMQ SSO, TimescaleDB, step-ca health check
9. **cert-manager**: TLS for all Ingress endpoints

---

## References

- [Keycloak Kubernetes Operator](https://www.keycloak.org/operator/installation)
- [cert-manager step-ca Issuer](https://github.com/smallstep/step-issuer)
- [RabbitMQ Cluster Operator](https://www.rabbitmq.com/kubernetes/operator/operator-overview)
- [External Secrets Operator](https://external-secrets.io/)
- [kompose](https://kompose.io/) — Docker Compose → K8s manifests
- CDM Skills: `.github/skills/cdm-keycloak/SKILL.md`, `.github/skills/cdm-step-ca/SKILL.md`
