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
