/**
 * JWT verification using Keycloak's JWKS endpoint.
 *
 * Returns a factory so that tests can inject their own signing-key resolver
 * without touching the real Keycloak instance.
 */
import type { JwtHeader, JwtPayload } from "jsonwebtoken";
import jwt from "jsonwebtoken";
import JwksRsa from "jwks-rsa";

export interface AuthConfig {
  jwksUri: string;
  audience: string;
}

/** A function that resolves a signing key for the given JWT header. */
export type GetKeyFn = (
  header: JwtHeader,
  callback: (err: Error | null, key?: string) => void
) => void;

/**
 * Create a `verifyToken` function bound to the given JWKS URI and audience.
 *
 * @param authConfig - JWKS URI and expected audience claim.
 * @param getKeyFn   - Optional override for the signing-key resolver (useful in tests).
 */
export function createVerifier(
  authConfig: AuthConfig,
  getKeyFn?: GetKeyFn
): (token: string) => Promise<JwtPayload> {
  const resolveKey: GetKeyFn =
    getKeyFn ??
    (() => {
      const client = JwksRsa({ jwksUri: authConfig.jwksUri, cache: true, rateLimit: true });
      return (header: JwtHeader, callback: (err: Error | null, key?: string) => void) => {
        client.getSigningKey(header.kid, (err, key) => {
          if (err) {
            callback(err);
            return;
          }
          callback(null, key?.getPublicKey());
        });
      };
    })();

  return function verifyToken(token: string): Promise<JwtPayload> {
    return new Promise((resolve, reject) => {
      jwt.verify(
        token,
        resolveKey,
        { audience: authConfig.audience },
        (err, decoded) => {
          if (err) {
            reject(err);
          } else {
            resolve(decoded as JwtPayload);
          }
        }
      );
    });
  };
}
