"""
Tiny OIDC discovery-document proxy for pgAdmin → Keycloak integration.

Problem: Keycloak's discovery document returns an external (Codespaces) URL
for 'jwks_uri'. Docker containers cannot access that URL without browser-based
GitHub authentication (port-forwarding auth wall). This proxy fetches the real
discovery document from the internal Keycloak endpoint and replaces 'jwks_uri'
with the internal Keycloak URL so pgAdmin/authlib can fetch JWKS without going
through the public internet.
"""

import http.server
import json
import logging
import os
import urllib.error
import urllib.request

KEYCLOAK_INTERNAL = os.environ.get(
    "KEYCLOAK_INTERNAL_URL",
    "http://keycloak:8080",
)
REALM = os.environ.get("KEYCLOAK_REALM", "provider")
DISCOVERY_PATH = f"/auth/realms/{REALM}/.well-known/openid-configuration"
JWKS_PATH = f"/auth/realms/{REALM}/protocol/openid-connect/certs"
PORT = int(os.environ.get("PROXY_PORT", "9099"))

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("oidc-proxy")


class OIDCProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path.rstrip("/") not in ("", "/openid-configuration"):
            self.send_response(404)
            self.end_headers()
            return

        try:
            resp = urllib.request.urlopen(
                f"{KEYCLOAK_INTERNAL}{DISCOVERY_PATH}", timeout=5
            )
            doc: dict = json.loads(resp.read())
        except urllib.error.URLError as exc:
            log.error("Cannot reach Keycloak: %s", exc)
            self.send_response(502)
            self.end_headers()
            return

        # Rewrite jwks_uri to internal URL so pgAdmin can reach it
        doc["jwks_uri"] = f"{KEYCLOAK_INTERNAL}{JWKS_PATH}"
        log.info(
            "Serving discovery doc (jwks_uri → %s%s)", KEYCLOAK_INTERNAL, JWKS_PATH
        )

        body = json.dumps(doc).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args) -> None:  # suppress default access log
        pass


if __name__ == "__main__":
    log.info("OIDC proxy listening on :%d", PORT)
    log.info("Upstream discovery: %s%s", KEYCLOAK_INTERNAL, DISCOVERY_PATH)
    http.server.HTTPServer(("0.0.0.0", PORT), OIDCProxyHandler).serve_forever()
