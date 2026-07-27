/**
 * Request-memoized guard resolution (OPS-168, CG-S8-OPS-002). Same `React.cache()`
 * dedupe rationale as `resolve-commercial-access.server.ts` (COM-143) -- the
 * Operations layout and every nested Job Order page within one request share this
 * one resolution rather than each re-running the guard's own Supabase/RPC round-trips.
 */

import { cache } from "react";
import { resolveOperationsAccess, type OperationsGuardResult } from "./operations-guard.ts";
import { buildOperationsGuardDeps } from "./operations-guard-deps.server.ts";

export const resolveOperationsAccessForRequest = cache(async (tenantSlug: string): Promise<OperationsGuardResult> => {
  const deps = await buildOperationsGuardDeps();
  return resolveOperationsAccess(deps, tenantSlug);
});
