/**
 * Unit tests for src/auth.ts – JWT verification.
 *
 * We bypass jwks-rsa and inject a custom getKeyFn so that tests run offline.
 */
import type { JwtHeader, JwtPayload } from "jsonwebtoken";
import jwt from "jsonwebtoken";
import { createVerifier } from "../src/auth";

// ── Test keys ──────────────────────────────────────────────────────────────

const SECRET = "test-secret-key-for-hs256-only";

function makeToken(claims: object, expiresInSeconds = 60): string {
  return jwt.sign(claims, SECRET, { algorithm: "HS256", expiresIn: expiresInSeconds });
}

/** A GetKeyFn that always resolves with our shared secret (HMAC). */
function alwaysResolveKey(
  _header: JwtHeader,
  callback: (err: Error | null, key?: string) => void
): void {
  callback(null, SECRET);
}

/** A GetKeyFn that always fails (simulates JWKS fetch error). */
function alwaysRejectKey(
  _header: JwtHeader,
  callback: (err: Error | null, key?: string) => void
): void {
  callback(new Error("JWKS fetch failed"));
}

// ── Tests ──────────────────────────────────────────────────────────────────

describe("createVerifier", () => {
  const verifyToken = createVerifier(
    { jwksUri: "http://localhost/certs", audience: "terminal-proxy" },
    alwaysResolveKey
  );

  it("resolves with the JWT payload for a valid token", async () => {
    const token = makeToken({ sub: "user-1", aud: "terminal-proxy" });
    const payload = await verifyToken(token);
    expect(payload.sub).toBe("user-1");
  });

  it("resolves with custom claims", async () => {
    const token = makeToken({
      sub: "user-2",
      aud: "terminal-proxy",
      preferred_username: "alice",
    });
    const payload = await verifyToken(token);
    expect((payload as JwtPayload & { preferred_username: string }).preferred_username).toBe(
      "alice"
    );
  });

  it("rejects an expired token", async () => {
    // Sign with -1s TTL → already expired
    const token = jwt.sign(
      { sub: "user-3", aud: "terminal-proxy" },
      SECRET,
      { algorithm: "HS256", expiresIn: -1 }
    );
    await expect(verifyToken(token)).rejects.toThrow(/expired/i);
  });

  it("rejects a token with a wrong audience", async () => {
    const token = makeToken({ sub: "user-4", aud: "other-service" });
    await expect(verifyToken(token)).rejects.toThrow(/audience/i);
  });

  it("rejects a token with an invalid signature", async () => {
    const token = makeToken({ sub: "user-5", aud: "terminal-proxy" });
    const tampered = token.slice(0, -5) + "XXXXX";
    await expect(verifyToken(tampered)).rejects.toThrow();
  });

  it("rejects when the key resolver fails (JWKS unavailable)", async () => {
    const failingVerifier = createVerifier(
      { jwksUri: "http://localhost/certs", audience: "terminal-proxy" },
      alwaysRejectKey
    );
    const token = makeToken({ sub: "user-6", aud: "terminal-proxy" });
    await expect(failingVerifier(token)).rejects.toThrow("JWKS fetch failed");
  });
});
