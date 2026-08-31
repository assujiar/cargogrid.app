/**
 * Request client-IP resolution for the IP-allowlist control (ISS-2026-302).
 *
 * WHY THIS EXISTS AT ALL
 *
 *   `app.assert_ip_allowed(tenant, client_ip, scope, label)` needs the caller's own address,
 *   and the database cannot obtain one. PostgREST sees the Next.js server as its client, so
 *   `request.headers` inside an RPC would report the server's address, not the person's --
 *   which is why every IP-gated function takes an explicit trailing `p_client_ip` instead.
 *   The only place the real address exists is the request that reached the server, and this
 *   module is the one place that reads it.
 *
 * WHICH HEADER, AND WHY THE ORDER MATTERS
 *
 *   `x-forwarded-for` is written by whoever sent the request. A browser can put anything in
 *   it, and a proxy APPENDS rather than replaces -- so on a spoofed request the list reads
 *   `<attacker's invention>, <real address the proxy observed>`. Taking the FIRST entry, the
 *   conventional "client IP" idiom, would therefore let anyone claim to be inside the
 *   allowlist by sending one header. For an access control that is not a subtlety, it is the
 *   whole thing.
 *
 *   So: `x-real-ip` first, because the hosting platform sets it and a client cannot forge a
 *   header the proxy overwrites; then the LAST entry of `x-forwarded-for`, which is the hop
 *   the nearest trusted proxy appended, never the first.
 *
 * FAILING TO A NULL IS DELIBERATE, AND IS NOT FAILING OPEN
 *
 *   Outside a request -- a unit test, a background job, a scheduled sweep -- there is no
 *   address to report, and `resolveRequestClientIp` returns null. The gated functions treat a
 *   null address as "no address supplied" and skip the check, exactly as they did before this
 *   control existed. That is the correct answer: an allowlist is a statement about where a
 *   PERSON may act from, and a scheduled sweep has no location to judge. Enforcement of who
 *   may act at all remains the authority check, which never depends on this value.
 */

/** Headers this module will read, in the order it trusts them. Exported for the test. */
export const CLIENT_IP_HEADERS = ["x-real-ip", "x-forwarded-for"] as const;

/**
 * Pure core: turn the two header values into one address, or null.
 *
 * Kept separate from the request plumbing so the trust decision above is testable without a
 * running server -- the ordering rule is the security-relevant part, and it should not need a
 * Next.js runtime to prove.
 */
export function selectClientIp(realIp: string | null | undefined, forwardedFor: string | null | undefined): string | null {
  const direct = realIp?.trim();
  if (direct) return direct;

  // Last entry, not first: see the header note above.
  const hops = (forwardedFor ?? "")
    .split(",")
    .map((hop) => hop.trim())
    .filter((hop) => hop.length > 0);
  return hops.length > 0 ? (hops[hops.length - 1] as string) : null;
}

/**
 * Read the current request's client address, or null when there is no request in scope.
 *
 * `next/headers` is imported dynamically because this module is reached from
 * `server/mutations/*`, which the unit-test suite loads under a plain Node runtime with no
 * Next.js resolution. A static import would turn every one of those tests into a module-load
 * failure for a value they neither set nor assert.
 */
export async function resolveRequestClientIp(): Promise<string | null> {
  try {
    const { headers } = await import("next/headers");
    const requestHeaders = await headers();
    return selectClientIp(requestHeaders.get("x-real-ip"), requestHeaders.get("x-forwarded-for"));
  } catch {
    return null;
  }
}
