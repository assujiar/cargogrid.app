/**
 * Request-memoized guard resolution (PRC-251, CG-S11-PRC-002). Same `React.cache()`
 * dedupe rationale as `resolve-commercial-access.server.ts` (COM-143) -- the
 * Procurement layout and every nested vendor page within one request share this one
 * resolution rather than each re-running the guard's own Supabase/RPC round-trips.
 */

import { cache } from "react";
import { resolveProcurementAccess, type ProcurementGuardResult } from "./procurement-guard.ts";
import { buildProcurementGuardDeps } from "./procurement-guard-deps.server.ts";

export const resolveProcurementAccessForRequest = cache(async (tenantSlug: string): Promise<ProcurementGuardResult> => {
  const deps = await buildProcurementGuardDeps();
  return resolveProcurementAccess(deps, tenantSlug);
});
