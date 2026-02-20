/**
 * Unit tests for src/ipResolver.ts – device ID → WireGuard IP lookup.
 */
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createFileIpResolver } from "../src/ipResolver";

// ── Helpers ────────────────────────────────────────────────────────────────

function writePeersFile(dir: string, peers: Record<string, string>): string {
  const filePath = join(dir, "cdm_peers.json");
  writeFileSync(filePath, JSON.stringify(peers, null, 2));
  return filePath;
}

const TMP_DIR = join(tmpdir(), `terminal-proxy-test-${process.pid}`);
mkdirSync(TMP_DIR, { recursive: true });

// ── Tests ──────────────────────────────────────────────────────────────────

describe("createFileIpResolver", () => {
  it("returns the correct IP for a known device", () => {
    const peersPath = writePeersFile(TMP_DIR, {
      "dev-001": "10.13.13.2",
      "dev-002": "10.13.13.3",
    });
    const resolver = createFileIpResolver(peersPath);
    expect(resolver.resolve("dev-001")).toBe("10.13.13.2");
    expect(resolver.resolve("dev-002")).toBe("10.13.13.3");
  });

  it("returns null for an unknown device", () => {
    const peersPath = writePeersFile(TMP_DIR, { "dev-001": "10.13.13.2" });
    const resolver = createFileIpResolver(peersPath);
    expect(resolver.resolve("unknown-device")).toBeNull();
  });

  it("returns null when the peers file does not exist", () => {
    const resolver = createFileIpResolver("/nonexistent/path/cdm_peers.json");
    expect(resolver.resolve("dev-001")).toBeNull();
  });

  it("returns null when the peers file contains invalid JSON", () => {
    const filePath = join(TMP_DIR, "invalid.json");
    writeFileSync(filePath, "NOT_JSON{{{");
    const resolver = createFileIpResolver(filePath);
    expect(resolver.resolve("dev-001")).toBeNull();
  });

  it("returns null for an empty peers file", () => {
    const peersPath = writePeersFile(TMP_DIR, {});
    const resolver = createFileIpResolver(peersPath);
    expect(resolver.resolve("dev-001")).toBeNull();
  });

  it("re-reads the file on each call (reflects live updates)", () => {
    const peersPath = writePeersFile(TMP_DIR, { "dev-live": "10.13.13.4" });
    const resolver = createFileIpResolver(peersPath);
    expect(resolver.resolve("dev-live")).toBe("10.13.13.4");

    // Simulate iot-bridge-api adding a new device
    writeFileSync(
      peersPath,
      JSON.stringify({ "dev-live": "10.13.13.4", "dev-new": "10.13.13.5" }, null, 2)
    );
    expect(resolver.resolve("dev-new")).toBe("10.13.13.5");
  });
});
