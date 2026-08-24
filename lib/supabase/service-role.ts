/**
 * Service-role Supabase client factory (PLT-135, CG-S6-PLT-032). `SUPABASE_SERVICE_ROLE_KEY`
 * is server-only (no `NEXT_PUBLIC_` prefix) and this file must never be imported from a
 * Client Component. `scripts/env/client-guard.ts`'s `assertServerOnly()` is only a
 * runtime `typeof window` check, not a static bundle scan, and does not target this
 * import path specifically -- the real static control is eslint.config.js's
 * `serviceRoleImportGuard` `no-restricted-imports` rule (ISS-2026-168), which flags
 * any import of this module regardless of caller.
 *
 * Every privileged platform RPC in this repository (`app.resolve_access_context`,
 * `app.evaluate_permission`, and every mutation function across every migration) is
 * granted to `service_role` only, never `authenticated` -- the established "explicit
 * actor, service-role execution" architecture this entire backend already uses (the
 * caller's real identity is authenticated via the RLS-scoped client -- see
 * `lib/supabase/server.ts` -- then passed explicitly as a parameter to a service-role
 * RPC call, never inferred from `auth.uid()` inside the privileged function itself).
 * This client is not session-bound (no cookies) since it never relies on RLS.
 */

import { createClient } from "@supabase/supabase-js";

function requireEnv(name: "NEXT_PUBLIC_SUPABASE_URL" | "SUPABASE_SERVICE_ROLE_KEY"): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is not set -- see .env.example`);
  }
  return value;
}

export function createSupabaseServiceRoleClient() {
  return createClient(requireEnv("NEXT_PUBLIC_SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
