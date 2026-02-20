/**
 * Maps a device ID to its WireGuard VPN IP address.
 *
 * Reads from the ``cdm_peers.json`` file maintained by iot-bridge-api's
 * WireGuardConfig class.  The file format is a plain JSON object:
 *
 * ```json
 * {
 *   "device-001": "10.13.13.2",
 *   "device-002": "10.13.13.3"
 * }
 * ```
 */
import { readFileSync } from "node:fs";

export interface IpResolver {
  resolve(deviceId: string): string | null;
}

/**
 * Create an IP resolver that reads from a JSON peers database file.
 *
 * @param peersDbPath - Absolute path to cdm_peers.json.
 */
export function createFileIpResolver(peersDbPath: string): IpResolver {
  return {
    resolve(deviceId: string): string | null {
      try {
        const content = readFileSync(peersDbPath, "utf-8");
        const peers = JSON.parse(content) as Record<string, string>;
        return peers[deviceId] ?? null;
      } catch {
        // File absent or parse error – device not yet provisioned
        return null;
      }
    },
  };
}
