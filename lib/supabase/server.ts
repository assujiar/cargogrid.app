/**
 * Server-side Supabase client factory (PLT-135, CG-S6-PLT-032). Follows Supabase's own
 * documented Next.js App Router pattern (`getAll`/`setAll`, not the deprecated
 * `get`/`set`/`remove` trio) -- reads/writes the session cookie Next's own `cookies()`
 * (`next/headers`) exposes, using `lib/auth/session-cookie-options.ts`'s already-decided
 * attributes (PLT-107) rather than a second, competing cookie-options source.
 *
 * A new client is created per request (Supabase's own documented requirement -- never
 * shared/cached across requests). `setAll` is called from Server Actions/Route Handlers
 * (where Next allows writing cookies); called from a plain Server Component render it
 * throws, caught and ignored below -- the session write is simply deferred to whichever
 * Server Action/Route Handler runs next, the same graceful-no-op Supabase's own docs
 * describe. **Disclosed gap**: a `middleware.ts` that proactively refreshes an
 * expiring session on every request is not built in this checkpoint (PLT-135 §11's
 * "bounded" scope) -- deferred to whichever future checkpoint first needs
 * long-idle-session refresh; login/logout (this checkpoint's own Server Actions) work
 * correctly without it.
 */

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { buildSessionCookieOptions } from "../auth/session-cookie-options.ts";

function requireEnv(name: "NEXT_PUBLIC_SUPABASE_URL" | "NEXT_PUBLIC_SUPABASE_ANON_KEY"): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is not set -- see .env.example`);
  }
  return value;
}

/** RLS-scoped client (the `anon` key, session-bound) -- every query through this client is subject to the requesting principal's own RLS policies, never a service-role bypass. */
export async function createSupabaseServerClient() {
  const cookieStore = await cookies();
  const sessionCookieOptions = buildSessionCookieOptions({ isProduction: process.env.NODE_ENV === "production" });

  return createServerClient(requireEnv("NEXT_PUBLIC_SUPABASE_URL"), requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY"), {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, { ...sessionCookieOptions, ...options });
          }
        } catch {
          // Called from a Server Component render, where Next.js does not allow
          // writing cookies -- see this file's own header.
        }
      },
    },
  });
}
