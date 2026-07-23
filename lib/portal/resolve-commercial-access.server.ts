/**
 * Request-memoized guard resolution (COM-143, CG-S7-COM-002). Same `React.cache()`
 * dedupe rationale as `resolve-tenant-admin-access.server.ts` (PLT-135) -- the
 * Commercial layout and every nested lead page within one request share this one
 * resolution rather than each re-running the guard's own Supabase/RPC round-trips.
 */

import { cache } from "react";
import { resolveCommercialAccess, type CommercialGuardResult } from "./commercial-guard.ts";
import { buildCommercialGuardDeps } from "./commercial-guard-deps.server.ts";

export const resolveCommercialAccessForRequest = cache(async (tenantSlug: string): Promise<CommercialGuardResult> => {
  const deps = await buildCommercialGuardDeps();
  return resolveCommercialAccess(deps, tenantSlug);
});
