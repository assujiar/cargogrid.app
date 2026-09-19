/**
 * Session cookie attribute contract (PLT-107, CG-S6-PLT-004). A pure function, not tied
 * to any live request/response cycle -- Next.js's own cookie-setting APIs (`cookies()`
 * from `next/headers`, `@supabase/ssr`'s `createServerClient`) accept exactly this shape.
 * No `app/` router exists yet in this repository (Phase 1's later portal capabilities,
 * `PLT-135`/`136`, are the first real consumers) -- this file establishes the *decision*
 * now, real and tested, rather than inventing a live-request test double prematurely.
 *
 * Values (Prompt 107 §16 "Secure cookies/tokens"):
 * - httpOnly: always true -- a session cookie must never be readable from client-side
 *   JavaScript (XSS exfiltration resistance).
 * - secure: environment-driven -- true in production (HTTPS-only transmission); false
 *   in non-production so local HTTP development still works (the browser silently drops
 *   a `Secure` cookie set over plain HTTP).
 * - sameSite: "lax" -- blocks cross-site POST/fetch CSRF while still allowing the cookie
 *   on a normal top-level navigation (an OAuth/magic-link redirect back into the app).
 * - path: "/" -- the session applies across the whole app, not one route subtree.
 * - maxAge: 7 days (604800s) -- **this checkpoint's own construction, disclosed, not
 *   derived from any ratified Tech Arch/RPD value** (none exists yet for session
 *   duration specifically). A reasonable, revisable default balancing security exposure
 *   window against re-authentication friction; formalize via ADR if a later checkpoint
 *   needs a different value.
 */

export const DEFAULT_SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 7;

export interface SessionCookieConfig {
  readonly isProduction: boolean;
  readonly maxAgeSeconds?: number;
}

export interface SessionCookieOptions {
  readonly httpOnly: true;
  readonly secure: boolean;
  readonly sameSite: "lax";
  readonly path: "/";
  readonly maxAge: number;
}

export function buildSessionCookieOptions(config: SessionCookieConfig): SessionCookieOptions {
  return {
    httpOnly: true,
    secure: config.isProduction,
    sameSite: "lax",
    path: "/",
    maxAge: config.maxAgeSeconds ?? DEFAULT_SESSION_MAX_AGE_SECONDS,
  };
}

/**
 * CG-AUDIT-2026-09-02 D3c. `@supabase/ssr`'s own `setAll` callback hands the cookie-write
 * site a library-constructed `options` object that ALWAYS carries its own `httpOnly:false`
 * and a 400-day `maxAge` for a real session cookie -- and, deliberately, `maxAge: 0` when
 * the library is *clearing* a cookie (logout, or replacing stale chunks), which must still
 * take effect or logout silently stops deleting the cookie. `lib/supabase/server.ts`
 * previously did `{ ...sessionCookieOptions, ...libraryOptions }`, so the library's object,
 * spread last, always won -- the exact inverse of this file's own documented contract
 * ("httpOnly: always true").
 *
 * This merge applies the security-relevant attributes (`httpOnly`, `secure`, `sameSite`,
 * `path`) from `sessionCookieOptions` unconditionally, and applies `sessionCookieOptions`'s
 * own `maxAge` UNLESS the library is explicitly clearing the cookie (`libraryOptions.maxAge
 * === 0`), in which case the clear is honored. Any other field the library sets (`domain`,
 * chunk-related keys) passes through untouched -- this narrows exactly the two attributes
 * the audit found inverted, without guessing at fields it did not.
 */
export function mergeSessionCookieOptions(sessionCookieOptions: SessionCookieOptions, libraryOptions: Readonly<Record<string, unknown>>): Record<string, unknown> {
  const isClearing = libraryOptions.maxAge === 0;
  return {
    ...libraryOptions,
    ...sessionCookieOptions,
    maxAge: isClearing ? 0 : sessionCookieOptions.maxAge,
  };
}
