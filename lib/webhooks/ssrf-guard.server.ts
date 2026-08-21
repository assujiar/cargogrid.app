/**
 * Runtime SSRF guard for the real webhook delivery worker (IAE-012 Tier C
 * fix, Batch 3). `app.validate_webhook_url()` (PLT-129) only rejects a
 * LITERAL private/loopback/link-local host at registration time -- its own
 * migration header disclosed this as deliberately partial: "It structurally
 * cannot defend against DNS-rebinding-based SSRF... since that requires a
 * live DNS resolution at actual delivery time, which belongs to the
 * not-yet-built delivery worker." IAE-012 built that worker without closing
 * the gap; this module closes it.
 *
 * Re-resolves the endpoint's hostname at the moment of dispatch and refuses
 * to deliver if ANY resolved address is private/loopback/link-local/
 * reserved -- a hostname that only starts resolving to an internal address
 * after registration (DNS rebinding) is caught here, not just at
 * registration time. `lookupHostname` is injectable so tests can simulate a
 * rebound hostname without depending on real, non-deterministic DNS.
 */

import { lookup as dnsLookup } from "node:dns/promises";
import type { LookupAddress } from "node:dns";
import { isIPv4, isIPv6 } from "node:net";

export interface SsrfCheckResult {
  readonly safe: boolean;
  readonly reason: string | null;
}

export type HostnameLookup = (hostname: string) => Promise<readonly LookupAddress[]>;

async function defaultLookup(hostname: string): Promise<readonly LookupAddress[]> {
  return dnsLookup(hostname, { all: true, verbatim: true });
}

function ipv4ToInt(ip: string): number {
  const parts = ip.split(".").map(Number);
  return ((parts[0]! << 24) | (parts[1]! << 16) | (parts[2]! << 8) | parts[3]!) >>> 0;
}

function inIpv4Range(ip: string, base: string, prefixLength: number): boolean {
  const mask = prefixLength === 0 ? 0 : (0xffffffff << (32 - prefixLength)) >>> 0;
  return (ipv4ToInt(ip) & mask) === (ipv4ToInt(base) & mask);
}

// 0.0.0.0/8 (this network), 10.0.0.0/8, 100.64.0.0/10 (CGNAT), 127.0.0.0/8
// (loopback), 169.254.0.0/16 (link-local, includes cloud metadata
// 169.254.169.254), 172.16.0.0/12, 192.0.0.0/24 (IETF protocol assignments),
// 192.168.0.0/16, 198.18.0.0/15 (benchmarking), 224.0.0.0/4 (multicast),
// 240.0.0.0/4 (reserved).
const IPV4_UNSAFE_RANGES: ReadonlyArray<readonly [string, number]> = [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["100.64.0.0", 10],
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.0.0.0", 24],
  ["192.168.0.0", 16],
  ["198.18.0.0", 15],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
];

export function isPrivateOrReservedIpv4(ip: string): boolean {
  return IPV4_UNSAFE_RANGES.some(([base, prefixLength]) => inIpv4Range(ip, base, prefixLength));
}

export function isPrivateOrReservedIpv6(ip: string): boolean {
  const lower = ip.toLowerCase();
  if (lower === "::1" || lower === "::") return true;
  if (lower.startsWith("fe80:") || lower.startsWith("fe8:") || lower.startsWith("fe9:") || lower.startsWith("fea:") || lower.startsWith("feb:")) return true; // fe80::/10 link-local
  if (/^f[cd][0-9a-f]{2}:/.test(lower)) return true; // fc00::/7 unique local
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(lower);
  if (mapped) return isPrivateOrReservedIpv4(mapped[1]!);
  return false;
}

function isUnsafeAddress(address: string, family: 4 | 6): boolean {
  return family === 4 ? isPrivateOrReservedIpv4(address) : isPrivateOrReservedIpv6(address);
}

/**
 * Refuses anything but a real, resolvable https:// host with no
 * private/loopback/link-local/reserved address among ALL of its resolved
 * addresses -- a single rebound/mixed answer is enough to refuse the whole
 * dispatch, since an attacker only needs one unsafe address to succeed.
 */
export async function checkWebhookDispatchUrlIsSafe(rawUrl: string, lookupHostname: HostnameLookup = defaultLookup): Promise<SsrfCheckResult> {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    return { safe: false, reason: "endpoint URL is not parseable" };
  }

  if (url.protocol !== "https:") {
    return { safe: false, reason: `endpoint URL scheme ${url.protocol} is not https:` };
  }

  const hostname = url.hostname;

  if (isIPv4(hostname)) {
    return isPrivateOrReservedIpv4(hostname) ? { safe: false, reason: `literal host ${hostname} is a private/reserved IPv4 address` } : { safe: true, reason: null };
  }
  if (isIPv6(hostname)) {
    return isPrivateOrReservedIpv6(hostname) ? { safe: false, reason: `literal host ${hostname} is a private/reserved IPv6 address` } : { safe: true, reason: null };
  }

  let addresses: readonly LookupAddress[];
  try {
    addresses = await lookupHostname(hostname);
  } catch (error) {
    return { safe: false, reason: `DNS resolution failed for ${hostname}: ${error instanceof Error ? error.message : "unknown error"}` };
  }

  if (addresses.length === 0) {
    return { safe: false, reason: `DNS resolution for ${hostname} returned no addresses` };
  }

  for (const { address, family } of addresses) {
    if (family !== 4 && family !== 6) continue;
    if (isUnsafeAddress(address, family)) {
      return { safe: false, reason: `${hostname} resolves to private/reserved address ${address}` };
    }
  }

  return { safe: true, reason: null };
}
