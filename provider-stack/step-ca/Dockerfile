# ── Stage 1: Build step-kms-plugin from source with HashiVault (OpenBao) support ─
# The pre-compiled release binary omits the hashivault KMS backend; building from
# source includes it (pure-Go HashiCorp Vault client, no CGO required).
ARG STEP_KMS_PLUGIN_VERSION=v0.16.0
FROM golang:1.24-alpine AS kms-plugin-builder
ARG STEP_KMS_PLUGIN_VERSION
RUN apk add --no-cache git
RUN git clone --depth 1 --branch "${STEP_KMS_PLUGIN_VERSION}" \
      https://github.com/smallstep/step-kms-plugin /src
WORKDIR /src
RUN go mod download
RUN CGO_ENABLED=0 go build -o /step-kms-plugin .

# ── Stage 2: Final image ──────────────────────────────────────────────────────
FROM smallstep/step-ca:latest

# Build context: repo root (set in docker-compose.yml)

# ── Install curl + jq (AppRole login); copy plugin binary from builder ────────
USER root
RUN apk add --no-cache curl jq
COPY --from=kms-plugin-builder /step-kms-plugin /usr/local/bin/step-kms-plugin
RUN chmod +x /usr/local/bin/step-kms-plugin

# ── Copy cert templates and provisioner init script ───────────────────────────
# Copy all step-ca certificate templates (leaf certs + sub-CA signer template)
COPY --chown=step:step provider-stack/step-ca/templates/ /home/step/templates/

# Copy consolidated init script that adds both leaf-cert AND sub-CA provisioners
COPY --chown=step:step provider-stack/step-ca/init-provisioners.sh /usr/local/bin/init-provisioners.sh
RUN chmod +x /usr/local/bin/init-provisioners.sh

# ── Custom entrypoint: AppRole auth + KMS-aware step-ca init ──────────────────
COPY --chmod=0755 provider-stack/step-ca/docker-entrypoint.sh /docker-entrypoint.sh
USER step
ENTRYPOINT ["/docker-entrypoint.sh"]
