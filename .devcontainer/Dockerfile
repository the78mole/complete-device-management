FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && mkdir -p /usr/local/share/ca-certificates/extra \
    && rm -rf /var/lib/apt/lists/*

COPY certs/*.crt certs/*.pem /usr/local/share/ca-certificates/extra/
