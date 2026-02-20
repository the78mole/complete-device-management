/**
 * Unit tests for src/server.ts – HTTP + WebSocket proxy server.
 *
 * All external dependencies (JWT verification, IP resolution, device WS) are
 * injected as mocks so no live Keycloak or ttyd instance is required.
 */
import http from "node:http";
import type { AddressInfo } from "node:net";
import type { JwtPayload } from "jsonwebtoken";
import { WebSocket } from "ws";
import { createProxyServer } from "../src/server";

// ── Helpers ────────────────────────────────────────────────────────────────

function buildServer(overrides?: {
  verifyToken?: (token: string) => Promise<JwtPayload>;
  resolveIp?: (deviceId: string) => string | null;
  connectToDevice?: (url: string) => WebSocket;
}) {
  return createProxyServer({
    verifyToken: overrides?.verifyToken ?? jest.fn().mockResolvedValue({ sub: "user-1" }),
    resolveIp: overrides?.resolveIp ?? jest.fn().mockReturnValue("10.13.13.2"),
    ttydPort: 7681,
    connectToDevice: overrides?.connectToDevice,
  });
}

function startServer(
  server: http.Server
): Promise<{ port: number; close: () => Promise<void> }> {
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address() as AddressInfo;
      resolve({
        port,
        close: () =>
          new Promise<void>((res, rej) =>
            server.close((err) => (err ? rej(err) : res()))
          ),
      });
    });
  });
}

function httpGet(url: string): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let body = "";
      res.on("data", (chunk: string) => (body += chunk));
      res.on("end", () => resolve({ status: res.statusCode ?? 0, body }));
    }).on("error", reject);
  });
}

/** Attempt a WebSocket upgrade and return the HTTP status code on rejection. */
function wsConnectStatus(url: string): Promise<number> {
  return new Promise((resolve) => {
    const ws = new WebSocket(url);
    ws.on("unexpected-response", (_req, res) => {
      resolve(res.statusCode ?? 0);
      ws.terminate();
    });
    ws.on("open", () => {
      // Should not happen in rejection tests, but handle gracefully
      resolve(101);
      ws.close();
    });
    ws.on("error", () => resolve(0));
  });
}

// ── HTTP Tests ─────────────────────────────────────────────────────────────

describe("GET /health", () => {
  it("returns 200 with a JSON liveness body", async () => {
    const server = buildServer();
    const { port, close } = await startServer(server);
    try {
      const { status, body } = await httpGet(`http://127.0.0.1:${port}/health`);
      expect(status).toBe(200);
      const parsed = JSON.parse(body) as Record<string, string>;
      expect(parsed.status).toBe("ok");
      expect(parsed.service).toBe("terminal-proxy");
    } finally {
      await close();
    }
  });

  it("returns 404 for unknown HTTP paths", async () => {
    const server = buildServer();
    const { port, close } = await startServer(server);
    try {
      const { status } = await httpGet(`http://127.0.0.1:${port}/unknown`);
      expect(status).toBe(404);
    } finally {
      await close();
    }
  });
});

// ── WebSocket Rejection Tests ──────────────────────────────────────────────

describe("WebSocket upgrade – rejection cases", () => {
  it("returns 404 when the path is not /terminal/<deviceId>", async () => {
    const server = buildServer();
    const { port, close } = await startServer(server);
    try {
      expect(await wsConnectStatus(`ws://127.0.0.1:${port}/other`)).toBe(404);
      expect(await wsConnectStatus(`ws://127.0.0.1:${port}/terminal`)).toBe(404);
    } finally {
      await close();
    }
  });

  it("returns 401 when the token query-param is missing", async () => {
    const server = buildServer();
    const { port, close } = await startServer(server);
    try {
      const status = await wsConnectStatus(
        `ws://127.0.0.1:${port}/terminal/dev-001`
      );
      expect(status).toBe(401);
    } finally {
      await close();
    }
  });

  it("returns 401 when the JWT is invalid", async () => {
    const server = buildServer({
      verifyToken: jest.fn().mockRejectedValue(new Error("invalid token")),
    });
    const { port, close } = await startServer(server);
    try {
      const status = await wsConnectStatus(
        `ws://127.0.0.1:${port}/terminal/dev-001?token=bad.jwt.here`
      );
      expect(status).toBe(401);
    } finally {
      await close();
    }
  });

  it("returns 404 when the device is not provisioned", async () => {
    const server = buildServer({
      resolveIp: jest.fn().mockReturnValue(null),
    });
    const { port, close } = await startServer(server);
    try {
      const status = await wsConnectStatus(
        `ws://127.0.0.1:${port}/terminal/unknown-dev?token=valid`
      );
      expect(status).toBe(404);
    } finally {
      await close();
    }
  });
});

// ── WebSocket Proxy Tests ──────────────────────────────────────────────────

describe("WebSocket upgrade – successful proxy", () => {
  it(
    "accepts the upgrade and pipes messages between client and mock device",
    async () => {
      // Start a mock echo server (simulates ttyd)
      const mockEchoHttpServer = http.createServer();
      const mockEchoWss = new WebSocket.Server({ server: mockEchoHttpServer });
      mockEchoWss.on("connection", (ws) => {
        ws.on("message", (data) => ws.send(data));
      });

      const mockDevicePort = await new Promise<number>((resolve) => {
        mockEchoHttpServer.listen(0, "127.0.0.1", () => {
          resolve((mockEchoHttpServer.address() as AddressInfo).port);
        });
      });

      // Start proxy, redirecting device connections to the echo server
      const server = buildServer({
        connectToDevice: (_url: string) =>
          new WebSocket(`ws://127.0.0.1:${mockDevicePort}`),
      });
      const { port, close } = await startServer(server);

      try {
        await new Promise<void>((resolve, reject) => {
          const clientWs = new WebSocket(
            `ws://127.0.0.1:${port}/terminal/dev-001?token=valid`
          );
          clientWs.on("open", () => clientWs.send("hello-from-browser"));
          clientWs.on("message", (data) => {
            expect(data.toString()).toBe("hello-from-browser");
            clientWs.close();
            resolve();
          });
          clientWs.on("error", reject);
        });
      } finally {
        await close();
        await new Promise<void>((res) => mockEchoHttpServer.close(() => res()));
      }
    },
    10_000 // 10 s timeout
  );
});
