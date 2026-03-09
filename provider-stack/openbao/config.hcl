# Provider-Stack – OpenBao Server Configuration
#
# This configuration is used in OPENBAO_MODE=standalone (default).
# In OPENBAO_MODE=agent the container runs as a proxy to an external Hub cluster
# and this file is not used.
#
# Design: software-only, no TPM required.
# The unseal key is derived from the Raft storage and persisted to
# /openbao/data/.init.json (volume-backed).  The container entrypoint
# auto-unseals on every restart.
#
# TLS: handled by Caddy (/vault/ path).  Internal communication uses plain HTTP.
# For direct-TLS on port 8200, uncomment the tls_* lines in the listener block.

storage "raft" {
  path    = "/openbao/data"
  node_id = "provider-node-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"
  # tls_cert_file = "/openbao/tls/openbao.crt"   # enable for direct-TLS mode
  # tls_key_file  = "/openbao/tls/openbao.key"
}

# Advertised address (used by Raft peers and for redirect URIs)
api_addr     = "http://openbao:8200"
cluster_addr = "http://openbao:8201"

# Web UI (served at /ui/ by OpenBao; proxied via Caddy at /vault/)
ui = true

# Token lease defaults
default_lease_ttl = "168h"  # 7 days
max_lease_ttl     = "720h"  # 30 days

# Log level (debug | info | warn | error)
log_level = "info"
