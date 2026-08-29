# Tenant-Stack – OpenBao Server Configuration
#
# OpenBao provides code-signing capabilities for the Tenant-Stack:
#   - Transit secrets engine: asymmetric key for OTA artifact / RAUC bundle signing
#   - KV-v2 secrets engine:   stores the code-signing certificate from the Tenant Sub-CA
#   - AppRole auth:           CI/CD pipelines authenticate to perform signing operations
#
# The code-signing certificate is issued by the Tenant step-ca (via openbao-cert-init)
# and stored at the KV-v2 path  code-signing/data/cert.
#
# TLS note: TLS termination is handled by Caddy (/vault/ path).
#           Internal service communication uses plain HTTP on the Docker network.
#
# Auto-unseal note: same as provider-stack – unseal key stored in /openbao/data/.init.json.

storage "raft" {
  path    = "/openbao/data"
  node_id = "tenant-node-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
}

api_addr     = "http://openbao:8200"
cluster_addr = "http://openbao:8201"

ui = true

default_lease_ttl = "168h"
max_lease_ttl     = "720h"

log_level = "info"
