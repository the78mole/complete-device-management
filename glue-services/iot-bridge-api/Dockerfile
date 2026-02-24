FROM python:3.14-slim

WORKDIR /app

# gcc is required by the cryptography package build
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

# Run as non-root
RUN useradd -r -u 1001 appuser && chown -R appuser:appuser /app

# The Python base image sets SSL_CERT_FILE to /etc/ssl/certs/ca-certificates.crt which
# lives in a root-only directory. Override to the world-readable bundle so the non-root
# appuser can establish outbound TLS connections (e.g. to step-ca).
ENV SSL_CERT_FILE=/etc/ssl/cert.pem \
    CURL_CA_BUNDLE=/etc/ssl/cert.pem \
    REQUESTS_CA_BUNDLE=/etc/ssl/cert.pem

USER appuser

EXPOSE 8000
# Use a shell wrapper so we can unconditionally redirect SSL cert env vars that
# some Docker environments inject into PID 1's environment at runtime,
# pointing to root-only certificate stores.
CMD ["/bin/sh", "-c", \
     "unset SSL_CERT_DIR NODE_EXTRA_CA_CERTS; \
      SSL_CERT_FILE=/etc/ssl/cert.pem; \
      REQUESTS_CA_BUNDLE=/etc/ssl/cert.pem; \
      CURL_CA_BUNDLE=/etc/ssl/cert.pem; \
      export SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE; \
      exec uvicorn app.main:app --host 0.0.0.0 --port 8000"]
