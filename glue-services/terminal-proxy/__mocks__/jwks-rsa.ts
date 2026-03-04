/**
 * Manual Jest stub for jwks-rsa v4 (ESM-only).
 *
 * jwks-rsa@4 uses ECMAScript module syntax which Jest's CommonJS runtime
 * cannot parse. Since auth.ts only calls JwksRsa() in the production
 * code-path (tests always inject their own getKeyFn), a lightweight CJS
 * stub is sufficient to keep the test suite working.
 */

const jwksClient = jest.fn(() => ({
  getSigningKey: jest.fn((_kid: string, cb: (err: Error | null, key?: { getPublicKey(): string }) => void) => {
    cb(null, { getPublicKey: () => "stub-public-key" });
  }),
}));

export default jwksClient;
module.exports = jwksClient;
module.exports.default = jwksClient;
