/**
 * Entry point – wires together config, auth, IP resolver, and the proxy server.
 */
import { config } from "./config";
import { createVerifier } from "./auth";
import { createFileIpResolver } from "./ipResolver";
import { createProxyServer } from "./server";

const verifyToken = createVerifier({
  jwksUri: config.authJwksUri,
  audience: config.authAudience,
});

const ipResolver = createFileIpResolver(config.peersDbPath);

const server = createProxyServer({
  verifyToken,
  resolveIp: ipResolver.resolve.bind(ipResolver),
  ttydPort: config.ttydPort,
});

server.listen(config.port, () => {
  console.log(`[terminal-proxy] listening on port ${config.port}`);
  console.log(`[terminal-proxy] JWKS URI: ${config.authJwksUri}`);
  console.log(`[terminal-proxy] peers DB: ${config.peersDbPath}`);
});
