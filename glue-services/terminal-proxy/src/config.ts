/**
 * Environment-variable-based configuration for the terminal proxy.
 *
 * All values are read at module load time so that tests can override them via
 * `process.env` before importing this module.
 */
export interface Config {
  /** TCP port this proxy listens on. */
  port: number;
  /** Port that ttyd runs on inside each edge device. */
  ttydPort: number;
  /** Keycloak JWKS URI used to verify incoming bearer tokens. */
  authJwksUri: string;
  /** Expected `aud` claim in the JWT. */
  authAudience: string;
  /** Absolute path to the cdm_peers.json file written by iot-bridge-api. */
  peersDbPath: string;
}

export const config: Config = {
  port: parseInt(process.env.PORT ?? "8090", 10),
  ttydPort: parseInt(process.env.TTYD_PORT ?? "7681", 10),
  authJwksUri: process.env.AUTH_JWKS_URI ?? "",
  authAudience: process.env.AUTH_AUDIENCE ?? "terminal-proxy",
  peersDbPath: process.env.PEERS_DB_PATH ?? "/wg-config/cdm_peers.json",
};
