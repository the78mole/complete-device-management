/**
 * HTTP server + WebSocket proxy.
 *
 * URL scheme accepted by this server:
 *
 *   ws://<host>:8090/terminal/<deviceId>?token=<Keycloak JWT>
 *
 * On successful JWT verification the proxy:
 *   1. Looks up the device's WireGuard VPN IP from cdm_peers.json.
 *   2. Opens a new WebSocket connection to ws://<vpnIp>:<ttydPort>.
 *   3. Pipes messages bidirectionally between the client and ttyd.
 *
 * HTTP GET /health returns a JSON liveness probe.
 */
import { createServer, type IncomingMessage, type Server } from "node:http";
import type { Duplex } from "node:stream";
import type { JwtPayload } from "jsonwebtoken";
import { WebSocket, WebSocketServer } from "ws";

export interface ServerDeps {
  /** Validates a JWT bearer token and resolves with the payload. */
  verifyToken: (token: string) => Promise<JwtPayload>;
  /** Returns the WireGuard VPN IP for a device, or null if unknown. */
  resolveIp: (deviceId: string) => string | null;
  /** Port that ttyd runs on inside edge devices. */
  ttydPort: number;
  /**
   * Factory that opens a WebSocket to the device (ttyd).
   * Defaults to `new WebSocket(url)`.  Override in tests.
   */
  connectToDevice?: (url: string) => WebSocket;
}

/** Parse the path `/terminal/<deviceId>` and return the device ID or null. */
function parseDeviceId(pathname: string): string | null {
  const parts = pathname.split("/").filter(Boolean);
  if (parts.length >= 2 && parts[0] === "terminal") {
    return parts[1];
  }
  return null;
}

/** Reject a WebSocket upgrade by writing an HTTP error response on the raw socket. */
function rejectUpgrade(socket: Duplex, statusCode: number, statusText: string): void {
  socket.write(
    `HTTP/1.1 ${statusCode} ${statusText}\r\nConnection: close\r\n\r\n`
  );
  socket.destroy();
}

/**
 * Create and return the HTTP server (not yet listening).
 * Call `server.listen(port)` to start it.
 */
export function createProxyServer(deps: ServerDeps): Server {
  const connect = deps.connectToDevice ?? ((url: string) => new WebSocket(url));

  const wss = new WebSocketServer({ noServer: true });

  const httpServer = createServer((_req, res) => {
    if (_req.url === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok", service: "terminal-proxy" }));
      return;
    }
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not Found");
  });

  httpServer.on(
    "upgrade",
    async (request: IncomingMessage, socket: Duplex, head: Buffer) => {
      const rawUrl = request.url ?? "/";
      const parsed = new URL(rawUrl, "ws://localhost");

      // ── Route check ───────────────────────────────────────────────────────
      const deviceId = parseDeviceId(parsed.pathname);
      if (!deviceId) {
        rejectUpgrade(socket, 404, "Not Found");
        return;
      }

      // ── JWT validation ────────────────────────────────────────────────────
      const token = parsed.searchParams.get("token");
      if (!token) {
        rejectUpgrade(socket, 401, "Unauthorized");
        return;
      }
      try {
        await deps.verifyToken(token);
      } catch {
        rejectUpgrade(socket, 401, "Unauthorized");
        return;
      }

      // ── Device IP lookup ──────────────────────────────────────────────────
      const vpnIp = deps.resolveIp(deviceId);
      if (!vpnIp) {
        rejectUpgrade(socket, 404, "Device Not Found");
        return;
      }

      // ── Upgrade + proxy ───────────────────────────────────────────────────
      wss.handleUpgrade(request, socket, head, (clientWs) => {
        const ttydUrl = `ws://${vpnIp}:${deps.ttydPort}`;
        const deviceWs = connect(ttydUrl);

        // Buffer messages sent before the device WS handshake completes
        const pending: Array<{ data: Buffer; isBinary: boolean }> = [];

        clientWs.on("message", (data: Buffer, isBinary: boolean) => {
          if (deviceWs.readyState === WebSocket.OPEN) {
            deviceWs.send(data, { binary: isBinary });
          } else {
            pending.push({ data, isBinary });
          }
        });

        deviceWs.on("open", () => {
          // Flush buffered messages
          for (const msg of pending) {
            if (deviceWs.readyState === WebSocket.OPEN) {
              deviceWs.send(msg.data, { binary: msg.isBinary });
            }
          }
          pending.length = 0;

          // Forward messages from ttyd → browser
          deviceWs.on("message", (data: Buffer, isBinary: boolean) => {
            if (clientWs.readyState === WebSocket.OPEN) {
              clientWs.send(data, { binary: isBinary });
            }
          });
        });

        // Tear down both sides on close or error
        clientWs.on("close", () => {
          if (deviceWs.readyState === WebSocket.OPEN) {
            deviceWs.close();
          }
        });
        deviceWs.on("close", () => {
          if (clientWs.readyState === WebSocket.OPEN) {
            clientWs.close(1001, "Device disconnected");
          }
        });
        clientWs.on("error", (err: Error) => {
          console.error("[terminal-proxy] client error:", err.message);
          if (deviceWs.readyState === WebSocket.OPEN) {
            deviceWs.close();
          }
        });
        deviceWs.on("error", (err: Error) => {
          console.error("[terminal-proxy] device error:", err.message);
          if (clientWs.readyState === WebSocket.OPEN) {
            clientWs.close(1011, "Device connection error");
          }
        });
      });
    }
  );

  return httpServer;
}
