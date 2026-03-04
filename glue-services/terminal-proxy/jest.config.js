/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["**/tests/**/*.test.ts"],
  collectCoverage: false,
  // jwks-rsa v4 is ESM-only and cannot be consumed by Jest's CommonJS runtime.
  // The manual stub in __mocks__/jwks-rsa.ts provides a CJS-compatible shim.
  moduleNameMapper: {
    "^jwks-rsa$": "<rootDir>/__mocks__/jwks-rsa.ts",
  },
};
